"""Measure computation in captured Godot waves; Python trains only the readout.

python research/analyze.py research/raw.json --out research/results
Requires NumPy and Matplotlib. No fitting of the optical geometry or wave model.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def nrmse(predicted, actual):
    return float(np.linalg.norm(predicted - actual) / max(np.linalg.norm(actual), 1e-30))


def propagate(bits, impulse):
    """Linear convolution along symbol time; preserves all within-cycle samples."""
    n = len(bits)
    fft_size = 1 << (n + len(impulse) - 2).bit_length()
    spectrum = np.fft.rfft(impulse, n=fft_size, axis=0)
    spectrum *= np.fft.rfft(bits, n=fft_size)[:, None, None]
    return np.fft.irfft(spectrum, n=fft_size, axis=0)[:n]


def fit_readout(train, valid, test, y_train, y_valid):
    """Training-only scaling and fit; validation chooses lambda; test is untouched."""
    center = train.mean(axis=0)
    scale = np.maximum(train.std(axis=0), 1e-12)
    a, b, c = [(x - center) / scale for x in (train, valid, test)]
    bias = float(y_train.mean())
    gram = a.T @ a / len(a)
    rhs = a.T @ (y_train - bias) / len(a)
    best = None
    for regularization in np.logspace(-8, 1, 10):
        weights = np.linalg.solve(gram + regularization * np.eye(gram.shape[0]), rhs)
        mse = float(np.mean((b @ weights + bias - y_valid) ** 2))
        if best is None or mse < best[0]:
            best = mse, float(regularization), weights
    return c @ best[2] + bias, best[1]


def accuracy(predicted, target):
    return float(np.mean((predicted >= 0.5) == target))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("--out", type=Path, default=Path("research/results"))
    args = parser.parse_args()
    raw_bytes = args.raw.read_bytes()
    data = json.loads(raw_bytes)
    args.out.mkdir(parents=True, exist_ok=True)
    period = data["period_steps"]
    washout = data["memory_symbols"]
    summary = {
        "schema_version": 1,
        "raw_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "godot_version": data["godot_version"],
        "model": data["model"], "grid": data["grid"],
        "period_steps": period, "washout_symbols": washout,
        "counts": {"train": 1200, "validation": 500, "test": 1000},
        "trials": 3, "noise": "none; ideal noiseless simulation",
        "target": "input[n-2] XOR input[n-3], evaluated after symbol n",
    }

    # Each matrix column is measured with one active source. Three further runs
    # are stepped independently in Godot, rather than constructed by superposition.
    experiment = data["matrix"]
    raw_fields = [np.asarray(run["field"]) for run in experiment["runs"]]
    ticks = experiment["first_sample_tick"] + np.arange(experiment["sample_count"])
    reference = np.exp(-2j * np.pi * ticks / period)
    coefficients = [2 * np.mean(f * reference[:, None], axis=0) for f in raw_fields]
    matrix = np.stack(coefficients[:2], axis=1)
    matrix_checks = []
    for i, run in enumerate(experiment["runs"][2:], 2):
        vector = np.asarray(run["input"])
        predicted = matrix @ vector
        field_prediction = raw_fields[0] * vector[0] + raw_fields[1] * vector[1]
        # Intensities of separately measured basis runs cannot simply be added.
        wrong_power = sum(vector[j] ** 2 * np.mean(raw_fields[j] ** 2, axis=0) for j in range(2))
        actual_power = np.mean(raw_fields[i] ** 2, axis=0)
        matrix_checks.append({"input": run["input"],
            "coherent_output_nrmse": nrmse(predicted, coefficients[i]),
            "full_waveform_nrmse": nrmse(field_prediction, raw_fields[i]),
            "incoherent_power_sum_nrmse": nrmse(wrong_power, actual_power)})
    assert max(x["full_waveform_nrmse"] for x in matrix_checks) < 1e-4, "Superposition check failed"
    summary["matrix"] = {"real": matrix.real.tolist(), "imaginary": matrix.imag.tolist(),
                         "checks": matrix_checks, "calibration": "fixed finite time window; not a steady-state scattering matrix"}

    impulses = {name: np.asarray(value["impulse_field"]) for name, value in data["reservoirs"].items()}
    summary["convolution_checks"] = {}
    for name, impulse in impulses.items():
        actual = np.asarray(data["reservoirs"][name]["direct_field"])
        predicted = propagate(data["reservoirs"][name]["direct_bits"], impulse)
        error = nrmse(predicted, actual)
        tail = float(np.sum(impulse[-16:] ** 2) / np.sum(impulse ** 2))
        summary["convolution_checks"][name] = {"direct_symbols": len(actual), "direct_field_nrmse": error,
            "direct_intensity_nrmse": nrmse(np.mean(predicted ** 2, axis=1), np.mean(actual ** 2, axis=1)),
            "last_16_symbols_energy_fraction": tail}
        assert error < 0.002, "Impulse convolution disagrees with direct Godot stepping"
        assert tail < 1e-4, "Captured impulse response is too short for this layout"

    scores = {}
    trial_details = []
    sample_trace = None
    phase = 2 * np.pi * (np.arange(period) + 1) / period
    for trial in range(3):
        # Separate RNG streams and zero initial states for all splits. Washout
        # excludes startup artifacts; there are no shared histories across splits.
        seeds = [1729 + 10000 * trial, 3253 + 10000 * trial, 7919 + 10000 * trial]
        bits = [np.random.default_rng(seed).integers(0, 2, count + washout)
                for seed, count in zip(seeds, summary["counts"].values())]
        targets = [(np.roll(u, 2) ^ np.roll(u, 3))[washout:] for u in bits]
        triple_targets = [(np.roll(u, 1) ^ np.roll(u, 2) ^ np.roll(u, 3))[washout:] for u in bits]
        feature_sets = {}
        # Linear electronic memory control and a deliberately sufficient quadratic
        # electronic control: a tiny digital circuit already solves this task.
        taps = [np.stack([np.roll(u, lag)[washout:] for lag in range(16)], axis=1) for u in bits]
        feature_sets["linear input delays"] = taps
        feature_sets["quadratic input delays"] = [np.column_stack([t, t[:, 2] * t[:, 3]]) for t in taps]
        feature_sets["current input only"] = [u[washout:, None] for u in bits]
        for name, impulse in impulses.items():
            fields = [propagate(u, impulse)[washout:] for u in bits]
            # No EWMA detector state: each power measurement averages ONLY this
            # symbol's samples. All inter-symbol memory must be in the wave field.
            feature_sets[f"{name}: intensity"] = [np.mean(f ** 2, axis=1) for f in fields]
            feature_sets[f"{name}: linear field"] = [np.column_stack([
                np.mean(f * np.cos(phase)[None, :, None], axis=1),
                np.mean(f * np.sin(phase)[None, :, None], axis=1)]) for f in fields]
        detail = {"seeds": seeds, "readouts": {}}
        for name, features in feature_sets.items():
            prediction, regularization = fit_readout(*features, *targets[:2])
            score = accuracy(prediction, targets[2])
            scores.setdefault(name, []).append(score)
            detail["readouts"][name] = {"test_accuracy": score, "lambda": regularization,
                                        "feature_count": features[0].shape[1]}
            if trial == 0 and name == "cavity: intensity":
                sample_trace = {"target": targets[2][:64].tolist(), "prediction": prediction[:64].tolist(),
                                "input": bits[2][washout:washout + 64].tolist()}
                native_run = data["reservoirs"]["cavity"]
                native_bits = np.asarray(native_run["direct_bits"])
                native_field = np.asarray(native_run["direct_field"])
                shortcut_field = propagate(native_bits, impulses["cavity"])
                native_features = np.mean(native_field[washout:] ** 2, axis=1)
                shortcut_features = np.mean(shortcut_field[washout:] ** 2, axis=1)
                check_prediction, _ = fit_readout(features[0], features[1],
                    np.vstack([native_features, shortcut_features]), *targets[:2])
                native_prediction, shortcut_prediction = np.split(check_prediction, 2)
                native_target = (np.roll(native_bits, 2) ^ np.roll(native_bits, 3))[washout:]
                summary["native_readout_check"] = {
                    "trial": 1, "symbols_after_washout": len(native_prediction),
                    "native_test_accuracy": accuracy(native_prediction, native_target),
                    "class_agreement_with_convolution": float(np.mean((native_prediction >= .5) == (shortcut_prediction >= .5))),
                    "max_prediction_difference": float(np.max(np.abs(native_prediction - shortcut_prediction))),
                }
        prediction, regularization = fit_readout(*feature_sets["cavity: intensity"], *triple_targets[:2])
        triple_score = accuracy(prediction, triple_targets[2])
        scores.setdefault("cavity: three-bit parity", []).append(triple_score)
        detail["three_bit_parity"] = {"test_accuracy": triple_score, "lambda": regularization}
        trial_details.append(detail)
        print(f"Trial {trial + 1}: cavity XOR {detail['readouts']['cavity: intensity']['test_accuracy']:.1%}; three-bit parity {triple_score:.1%}", flush=True)
    summary["accuracy"] = {name: {"runs": values, "mean": float(np.mean(values)),
                                 "std_across_three_runs": float(np.std(values, ddof=1))}
                           for name, values in scores.items()}
    summary["trial_details"] = trial_details
    summary["first_test_trace"] = sample_trace
    summary["limits"] = [
        "Scalar toy model, not calibrated Maxwell physics or hardware evidence.",
        "Train/validation/test sequences use linear convolution of a measured Godot impulse response; a separate direct Godot sequence validates that shortcut.",
        "No detector EWMA, optical material nonlinearity, noise, fabrication errors, or hardware energy/speed measurement.",
        "Three independent input-stream trials; one preselected geometry and timing, no geometry optimization.",
        "XOR shows a primitive, not an advantage over software; the quadratic electronic baseline contains the required product explicitly.",
        "Fixed finite-window matrix calibration demonstrates an existing map, not programming an arbitrary requested matrix.",
    ]
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    make_plot(summary, raw_fields, impulses, args.out)
    print(json.dumps({"matrix_max_relative_error": max(x["coherent_output_nrmse"] for x in matrix_checks),
                      "accuracy": summary["accuracy"]}, indent=2))


def make_plot(summary, fields, impulses, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
        "axes.spines.top": False, "axes.spines.right": False})
    fig, axes = plt.subplots(2, 2, figsize=(13, 8.8), layout="constrained")
    fig.suptitle("Can the wave table compute?", fontsize=19, fontweight="bold")
    ax = axes[0, 0]
    prediction = .7 * fields[0][:, 1] - .4 * fields[1][:, 1]
    ax.plot(fields[2][:, 1], color="#2962d9", lw=2.5, label="Independent Godot run")
    ax.plot(prediction, color="#e68b13", lw=1.5, ls="--", label="Measured matrix prediction")
    ax.set(title="1. Superposition predicts a new input", xlabel="Step in measurement window", ylabel="Signed field at probe 2")
    ax.legend(fontsize=9, loc="upper right")
    ax = axes[0, 1]
    for name, impulse in impulses.items():
        energy = np.mean(impulse ** 2, axis=(1, 2))
        ax.semilogy(energy / energy.max(), label=name.title(), lw=2)
    ax.set(title="2. A pulse leaves a fading wave history", xlabel="Symbols after a one-symbol drive", ylabel="Mean-square field / peak", ylim=(1e-10, 2))
    ax.legend()
    ax = axes[1, 0]
    names = ["current input only", "linear input delays", "cavity: linear field", "empty: intensity", "cavity: intensity", "quadratic input delays", "cavity: three-bit parity"]
    means = [summary["accuracy"][n]["mean"] * 100 for n in names]
    deviations = [summary["accuracy"][n]["std_across_three_runs"] * 100 for n in names]
    ax.barh(names, means, xerr=deviations, color=["#a1a8b5"] * 3 + ["#72acb5", "#2962d9", "#7d9d75", "#c490bb"], capsize=3)
    ax.axvline(50, color="#777", ls=":", label="Chance")
    for i, mean in enumerate(means):
        ax.text(mean + deviations[i] + 1.5, i, f"{mean:.1f}%", va="center", fontsize=9)
    ax.invert_yaxis()
    ax.set(title="3. Held-out sequence recognition", xlabel="Test accuracy (%) · mean ± SD over 3 streams", xlim=(0, 116))
    ax.set_xticks([0, 25, 50, 75, 100])
    ax = axes[1, 1]
    trace = summary["first_test_trace"]
    ax.step(range(64), trace["target"], where="mid", color="#172940", lw=1.5, label="Wanted: bit[n−2] XOR bit[n−3]")
    ax.plot(trace["prediction"], "o", color="#2962d9", ms=3.5, label="Cavity intensity + trained readout")
    ax.axhline(.5, color="#777", ls=":")
    ax.set(title="4. Predictions on an unseen bit stream", xlabel="Test symbol (first 64, trial 1)", ylabel="Readout; threshold = 0.5")
    ax.legend(fontsize=8, loc="upper right")
    fig.get_layout_engine().set(rect=(0, .04, 1, .97))
    fig.text(.5, .014, "Ideal noiseless toy experiment. Geometry is fixed. Training and detection are digital; this is not a hardware performance claim.", ha="center", fontsize=9)
    fig.savefig(output / "computation.png", dpi=160)
    plt.close(fig)


if __name__ == "__main__":
    main()
