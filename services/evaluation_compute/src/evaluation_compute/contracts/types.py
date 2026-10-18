from typing import Annotated, Literal

from pydantic import BeforeValidator, Field, StrictFloat, StrictInt

JsonFiniteNumber = Annotated[
    StrictInt | StrictFloat,
    Field(allow_inf_nan=False),
]


def require_integer_token(value: object) -> object:
    if type(value) is not int:
        raise ValueError("schema_version must use an integer JSON token")
    return value


StrictSchemaVersion = Annotated[Literal[1], BeforeValidator(require_integer_token)]

IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"
