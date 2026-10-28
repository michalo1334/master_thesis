# Third-party warning only.
#
# deps/gust/lib/gust/flows/task.ex declares `logs: [Gust.Flows.Log.t()]`, but the
# Gust.Flows.Log module defines no `t/0` type. The dependency is unmodified here,
# so the ignore names that file, that warning, and that one type reference.
[
  {"lib/gust/flows/task.ex", "Unknown type: Gust.Flows.Log.t/0."}
]
