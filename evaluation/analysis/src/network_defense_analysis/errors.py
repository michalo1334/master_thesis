"""Public analysis errors."""

class AnalysisError(ValueError):
    """Raised when an export does not satisfy the analysis contract."""

def _error(message: str) -> AnalysisError:
    return AnalysisError(message)

__all__ = ["AnalysisError", "_error"]
