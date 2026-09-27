# Contributing

Thanks for your interest in improving FormBuddy!

## Development setup

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
pytest
```

## Adding a new exercise analyzer

1. Create `src/formbuddy/analyzers/<exercise>.py` implementing the
   `ExerciseAnalyzer` interface (`analyze(frames: list[Frame]) -> ExerciseReport`).
2. Register it in `src/formbuddy/pipeline.py`: `ANALYZERS = {"squat": SquatAnalyzer, "<exercise>": <Exercise>Analyzer}`.
3. Add tests in `tests/test_<exercise>.py` using synthetic landmark trajectories
   (see `tests/test_squat.py` for the pattern).
4. Update the README's supported-exercises list.

## Guidelines

- Keep analyzers pure: no I/O, no MediaPipe imports — work on landmark arrays.
- Every analyzer needs tests with synthetic trajectories before it lands.
- Run the full suite (`pytest`) before committing.
