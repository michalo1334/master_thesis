defmodule NetworkDefense.Vec2 do
  import Kernel, except: [length: 1]

  def sub({ax, ay}, {bx, by}) do
    {ax - bx, ay - by}
  end

  def add({ax, ay}, {bx, by}) do
    {ax + bx, ay + by}
  end

  def add({ax, ay}, n) when is_float(n) do
    {ax + n, ay + n}
  end

  def add(n, {ax, ay}) when is_float(n) do
    {n + ax, n + ay}
  end

  def mul({ax, ay}, n) when is_float(n) do
    {ax * n, ay * n}
  end

  def mul(n, {ax, ay}) when is_float(n) do
    {n * ax, n * ay}
  end

  def scale({x, y}, s) when is_float(s) do
    {x * s, y * s}
  end

  def length({x, y}) do
    :math.sqrt(x * x + y * y)
  end

  def normalize({x, y} = vec2) do
    length = length(vec2)
    {x / length, y / length}
  end

  def force_magnitude(vec2, strength) do
    strength / Float.pow(length(vec2), 2)
  end
end
