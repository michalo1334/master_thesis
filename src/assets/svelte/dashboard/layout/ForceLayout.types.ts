export interface ForceParams {
  repulsion: number;
  linkDistance: number;
  collisionRadius: number;
  centerStrength: number;
  alphaDecay: number;
}

export const defaultForceParams: ForceParams = {
  repulsion: -300,
  linkDistance: 150,
  collisionRadius: 80,
  centerStrength: 0.05,
  alphaDecay: 0.02,
};
