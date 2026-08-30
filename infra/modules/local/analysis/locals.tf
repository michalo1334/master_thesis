locals {
  image_name        = "${var.name_prefix}-analysis:dev"
  max_response_size = 50 * 1024 * 1024
  source_files = concat([
    ".dockerignore",
    "Dockerfile",
    "pyproject.toml",
    "uv.lock"
  ], sort(tolist(fileset(var.analysis_source_path, "src/**/*.py"))))
}
