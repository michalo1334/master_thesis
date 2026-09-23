export function pathsEqual(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return (
    left.length === right.length &&
    left.every((segment, index) => segment === right[index])
  );
}

export function pathStartsWith(
  path: readonly string[],
  prefix: readonly string[],
): boolean {
  return (
    prefix.length <= path.length &&
    prefix.every((segment, index) => segment === path[index])
  );
}
