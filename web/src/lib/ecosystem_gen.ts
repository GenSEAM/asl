import * as RT from "./rt";

export type TargetStatus =
  | { readonly tag: "active" }
  | { readonly tag: "inprogress" }
  | { readonly tag: "planned" };

export function active(): TargetStatus {
    return { tag: "active" };
}

export function inprogress(): TargetStatus {
    return { tag: "inprogress" };
}

export function planned(): TargetStatus {
    return { tag: "planned" };
}

export type Paradigm =
  | { readonly tag: "oop" }
  | { readonly tag: "functional" }
  | { readonly tag: "procedural" };

export function oop(): Paradigm {
    return { tag: "oop" };
}

export function functional(): Paradigm {
    return { tag: "functional" };
}

export function procedural(): Paradigm {
    return { tag: "procedural" };
}

export class TargetLanguage {
    readonly name: string;
    readonly slug: string;
    readonly paradigm: string;
    readonly description: string;
    constructor(f: { name: string; slug: string; paradigm: string; description: string }) {
        this.name = f.name;
        this.slug = f.slug;
        this.paradigm = f.paradigm;
        this.description = f.description;
    }
}

export function getTargetsCount(): bigint {
    return 7n;
}

export function calculateTokenSavings(modules: bigint, dailyCalls: bigint): bigint {
    const stdTokens = RT.mul(RT.mul(modules, 650n), dailyCalls);
    const asTokens = RT.mul(RT.mul(modules, 142n), dailyCalls);
    const monthlySaved = RT.mul(RT.sub(stdTokens, asTokens), 30n);
    return RT.div(monthlySaved, 1000000n);
}

export function formatBridgeName(p: Paradigm): string {
    return (() => {
        const t1 = p;
        if (t1.tag === "oop") {
            return "OOP Bridge (Schemas to Classes)";
        }
        if (t1.tag === "functional") {
            return "Functional Bridge (Pure S-Expressions)";
        }
        if (t1.tag === "procedural") {
            return "Procedural Bridge (Effects Tracking)";
        }
        return RT.nonExhaustive();
    })();
}

