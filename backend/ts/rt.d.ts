export type ASOption<T> = {
    readonly tag: "some";
    readonly value: T;
} | {
    readonly tag: "none";
};
export type ASResult<T, E> = {
    readonly tag: "ok";
    readonly value: T;
} | {
    readonly tag: "err";
    readonly value: E;
};
export declare const NONE: ASOption<never>;
export declare function some<T>(v: T): ASOption<T>;
export declare function ok<T>(v: T): ASResult<T, never>;
export declare function err<E>(e: E): ASResult<never, E>;
export declare class ASPair<A, B> {
    readonly first: A;
    readonly second: B;
    constructor(first: A, second: B);
}
export declare class ASThrown<E> extends Error {
    readonly value: E;
    constructor(value: E);
}
export interface ASMap<K, V> {
    readonly entries: ReadonlyMap<string, readonly [K, V]>;
}
export declare const MAP_EMPTY: ASMap<never, never>;
export declare function eq(a: unknown, b: unknown): boolean;
export declare function cmp(a: unknown, b: unknown): number;
type ASNum = bigint | number;
export declare function add<T extends ASNum>(a: T, b: T): T;
export declare function sub<T extends ASNum>(a: T, b: T): T;
export declare function mul<T extends ASNum>(a: T, b: T): T;
export declare function neg<T extends ASNum>(a: T): T;
export declare function absv<T extends ASNum>(a: T): T;
export declare function div<T extends ASNum>(a: T, b: T): T;
export declare function rem<T extends ASNum>(a: T, b: T): T;
export declare function checkedDiv<T extends ASNum>(a: T, b: T): ASOption<T>;
export declare function checkedRem<T extends ASNum>(a: T, b: T): ASOption<T>;
export declare function min<T>(a: T, b: T): T;
export declare function max<T>(a: T, b: T): T;
export declare function strLen(s: string): bigint;
export declare function concat(parts: readonly string[]): string;
export declare function chars(s: string): string[];
export declare function strRev(s: string): string;
export declare function split(s: string, sep: string): string[];
export declare function replace(s: string, from: string, to: string): string;
export declare function strSlice(s: string, a: bigint, b: bigint): ASOption<string>;
export declare function strIndexOf(s: string, sub: string): ASOption<bigint>;
export declare function fmtF64(x: number): string;
export declare function toI64(s: string): ASOption<bigint>;
export declare function toF64(s: string): ASOption<number>;
export declare function toI32(n: bigint): ASOption<bigint>;
export declare function fToI(x: number): ASOption<bigint>;
export declare function at<T>(xs: readonly T[], i: bigint): ASOption<T>;
export declare function tail<T>(xs: readonly T[]): ASOption<T[]>;
export declare function listSlice<T>(xs: readonly T[], a: bigint, b: bigint): ASOption<T[]>;
export declare function contains<T>(xs: readonly T[], x: T): boolean;
export declare function indexOf<T>(xs: readonly T[], x: T): ASOption<bigint>;
export declare function sort<T>(xs: readonly T[]): T[];
export declare function sortBy<T, K>(f: (x: T) => K, xs: readonly T[]): T[];
export declare function fold<A, B>(f: (acc: B, x: A) => B, init: B, xs: readonly A[]): B;
export declare function range(a: bigint, b: bigint): bigint[];
export declare function zip<A, B>(a: readonly A[], b: readonly B[]): ASPair<A, B>[];
export declare function sum<T extends ASNum>(xs: readonly T[]): T;
export declare function least<T>(xs: readonly T[]): ASOption<T>;
export declare function greatest<T>(xs: readonly T[]): ASOption<T>;
export declare function mGet<K, V>(m: ASMap<K, V>, k: K): ASOption<V>;
export declare function mSet<K, V>(m: ASMap<K, V>, k: K, v: V): ASMap<K, V>;
export declare function mDel<K, V>(m: ASMap<K, V>, k: K): ASMap<K, V>;
export declare function mHas<K, V>(m: ASMap<K, V>, k: K): boolean;
export declare function mSize<K, V>(m: ASMap<K, V>): bigint;
export declare function mKeys<K, V>(m: ASMap<K, V>): K[];
export declare function mValues<K, V>(m: ASMap<K, V>): V[];
export declare function mPairs<K, V>(m: ASMap<K, V>): ASPair<K, V>[];
export declare function mFrom<K, V>(ps: readonly ASPair<K, V>[]): ASMap<K, V>;
export declare function optOr<T>(o: ASOption<T>, d: T): T;
export declare function resOr<T, E>(r: ASResult<T, E>, d: T): T;
export declare function optMap<A, B>(f: (a: A) => B, o: ASOption<A>): ASOption<B>;
export declare function resMap<A, B, E>(f: (a: A) => B, r: ASResult<A, E>): ASResult<B, E>;
export declare function resMapErr<T, E, F>(f: (e: E) => F, r: ASResult<T, E>): ASResult<T, F>;
export declare function optToRes<T, E>(o: ASOption<T>, e: E): ASResult<T, E>;
export declare function resToOpt<T, E>(r: ASResult<T, E>): ASOption<T>;
export declare function unwrap<T, E>(r: ASResult<T, E>): T;
export declare function nonExhaustive(): never;
export type IoError = {
    readonly tag: "not-found";
} | {
    readonly tag: "permission-denied";
} | {
    readonly tag: "already-exists";
} | {
    readonly tag: "invalid-path";
} | {
    readonly tag: "interrupted";
} | {
    readonly tag: "other";
};
export declare function notFound(): IoError;
export declare function permissionDenied(): IoError;
export declare function alreadyExists(): IoError;
export declare function invalidPath(): IoError;
export declare function interrupted(): IoError;
export declare function other(): IoError;
export declare function codeToIoError(code: string | undefined): IoError;
export declare function readLine(): ASResult<ASOption<string>, IoError>;
export declare function readAll(): ASResult<string, IoError>;
export declare function print_(s: string): ASResult<void, IoError>;
export declare function println(s: string): ASResult<void, IoError>;
export declare function eprintln(s: string): ASResult<void, IoError>;
export declare function fileRead(path: string): ASResult<string, IoError>;
export declare function fileWrite(path: string, s: string): ASResult<void, IoError>;
export declare function fileAppend(path: string, s: string): ASResult<void, IoError>;
export declare function fileExists(path: string): boolean;
export declare function args(): string[];
export declare function mainExit(result: ASResult<unknown, IoError>): never;
export {};
//# sourceMappingURL=rt.d.ts.map