// Type-level fixture asserting the generated contract import modules compile
// under tsconfig's isolatedModules + verbatimModuleSyntax.
import type { DescribeManifestPayload } from "./contracts.generated/dashboard/evaluation";
import type * as EvaluationContracts from "./contracts.generated/dashboard/evaluation";

type Payload = DescribeManifestPayload;
type Reply = EvaluationContracts.DescribeManifestReply;
type Plan = EvaluationContracts.DescribeManifestPlan;
type PlanGroup = EvaluationContracts.DescribeManifestPlanGroup;

// Re-export to keep the fixture meaningful under strict build settings.
export type FixturePayload = Payload;
export type FixtureReply = Reply;
export type FixturePlan = Plan;
export type FixturePlanGroup = PlanGroup;
