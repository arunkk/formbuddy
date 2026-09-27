"""Allow ``python -m formbuddy`` to invoke the CLI."""

import sys

from formbuddy.cli import main

if __name__ == "__main__":
    sys.exit(main())
