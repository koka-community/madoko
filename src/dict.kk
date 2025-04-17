pub import std/data/linearmap

alias dict<m> = linearMap<string, m>

alias mdict<i> = ref<global, linearMap<string, i>>

fun @index(m: dict<m>, k: string): maybe<m>
  m.lookup(k)

val dict = LinearMap
val containsKey = contains-key
fun (++)(m1: dict<m>, m2: dict<m>): dict<m>
  m1 + m2.list