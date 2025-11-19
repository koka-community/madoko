import std/text/regex

pub struct matched
  index : int
  next : int
  matched : string
  groups : groups
  // groups : list<string>

pub struct groups
  internal: list<sslice>

fun @index(g: groups, i: int): exn string
  g.internal[i].maybe/unjust.string

fun startsWith(s: string, s2: string): bool
  s.starts-with(s2).bool

fun length(s: string): int
  s.count

fun endsWith(s: string, s2: string): bool
  s.ends-with(s2).bool

fun matchedOn(l : groups, i: int) : bool
  // TODO: Tim Bad
  False

fun str/find(s: string, regex: regex): exn maybe<matched>
  val res = exec(regex, s)
  match res
    [] -> Nothing
    Cons(first) ->
      val i = first.before.string.count
      val n = res.last.maybe/unjust.before.string.count
      Just(Matched(i, n, first.truncate.extend(n - i).string, Groups(res)))

val findAll = find-all

pub fun regexAlt( rxs : list<string> ) : regex
  regex( rxs.map(fn(r) { "(" ++ r ++ ")" }).join("|") )

fun substr(s: string, start: int, end: int = s.count): string
  s.slice.subslice(start, end).string

fun lastIndexOf(s: string, c: char): int
  s.list.last-index-of(c, 0).default(-1)

pub val string/replaceAll = regex/string/replace-all

fun list/last-index-of(l: list<char>, c: char, i: int): maybe<int>
  match l
    [] -> Nothing
    Cons(c1, rst) ->
      val c2 = last-index-of(rst, c, i + 1)
      match c2
        Just(ix) -> Just(ix)
        Nothing -> if c == c1 then Just(i) else Nothing