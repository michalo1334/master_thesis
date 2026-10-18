import math
from dataclasses import dataclass

import numpy as np
import numpy.typing as npt


@dataclass(frozen=True)
class CrossedStatistics:
    estimate: float
    lower: float
    upper: float
    raw_p_value: float
    informative: bool
    zero_width_interval: bool


def finite_sample_correction(
    alternative_plan_count: int,
    reference_plan_count: int,
    attack_count: int,
) -> float:
    row = max(
        alternative_plan_count / (alternative_plan_count - 1),
        reference_plan_count / (reference_plan_count - 1),
    )
    column = attack_count / (attack_count - 1)
    return math.sqrt(row * column)


def corrected_crossed_draws(
    alternative: npt.NDArray[np.float64],
    reference: npt.NDArray[np.float64],
    *,
    replicates: int,
    seed: int,
) -> npt.NDArray[np.float64]:
    alternative_count, attack_count = alternative.shape
    reference_count, reference_attack_count = reference.shape
    if reference_attack_count != attack_count:
        raise ValueError("crossed matrices must have equal attack-column counts")
    if alternative_count < 5 or reference_count < 5 or attack_count < 10:
        raise ValueError("crossed matrices do not meet calibrated sample minimums")

    observed = float(alternative.mean() - reference.mean())
    correction = finite_sample_correction(alternative_count, reference_count, attack_count)
    generator = np.random.default_rng(seed)
    values = np.empty(replicates, dtype=np.float64)

    for index in range(replicates):
        columns = generator.integers(0, attack_count, size=attack_count)
        alternative_rows = generator.integers(0, alternative_count, size=alternative_count)
        reference_rows = generator.integers(0, reference_count, size=reference_count)
        alternative_sample = alternative[np.ix_(alternative_rows, columns)]
        reference_sample = reference[np.ix_(reference_rows, columns)]
        raw = float(alternative_sample.mean() - reference_sample.mean())
        values[index] = observed + correction * (raw - observed)

    return values


def corrected_crossed_bootstrap(
    alternative: npt.NDArray[np.float64],
    reference: npt.NDArray[np.float64],
    *,
    replicates: int,
    confidence_level: float,
    seed: int,
) -> CrossedStatistics:
    interval_sequence, null_sequence = np.random.SeedSequence(seed).spawn(2)
    interval_seed = int(interval_sequence.generate_state(1)[0])
    null_seed = int(null_sequence.generate_state(1)[0])

    estimate = float(alternative.mean() - reference.mean())
    interval_draws = corrected_crossed_draws(
        alternative,
        reference,
        replicates=replicates,
        seed=interval_seed,
    )
    tail = (1.0 - confidence_level) / 2.0
    lower, upper = np.percentile(interval_draws, [tail * 100.0, (1.0 - tail) * 100.0])
    lower = float(lower)
    upper = float(upper)

    centered_alternative = alternative - alternative.mean()
    centered_reference = reference - reference.mean()
    null_draws = corrected_crossed_draws(
        centered_alternative,
        centered_reference,
        replicates=replicates,
        seed=null_seed,
    )
    extreme_count = int(np.count_nonzero(np.abs(null_draws) >= abs(estimate)))
    raw_p_value = float((1 + extreme_count) / (replicates + 1))

    informative = not (
        np.isclose(estimate, 0.0) and np.isclose(lower, 0.0) and np.isclose(upper, 0.0)
    )
    if not informative:
        raw_p_value = 1.0
    zero_width = bool(informative and np.isclose(lower, upper))

    return CrossedStatistics(
        estimate=estimate,
        lower=lower,
        upper=upper,
        raw_p_value=raw_p_value,
        informative=bool(informative),
        zero_width_interval=zero_width,
    )
