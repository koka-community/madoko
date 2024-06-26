/*---------------------------------------------------------------------------
  Copyright 2013 Daan Leijen, Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Attibute operations: parsing, transform text, expand keys, etc.
module attributes

import std/text/regex
import std/data/dict
import common
import entity
import expression

pub fun parseAttrs( attrStr : string, elemName : string = "", source : string = "" ) : attrs {
  if (attrStr == "" && elemName == "" && source=="") return attrsNone
  val attrs0 = Attrs() // source=source,classes=if (className=="") then [] else [className])
  attrs0.extendAttrs( (if (elemName!="") then "elem:'" ++ elemName ++ "'; " else "") ++ attrStr, source )
}

pub fun mergeDefault( attrs : attrs, def : attrs ) : attrs {
  def.extendAttrs(attrs.text, attrs.source)
}

abstract struct rules(
  rules: list<(pattern,string)>
)

struct pattern( 
  elem: string,
  name: string,
  classes: list<string>,
  attrselectors: list<expr>,
  weight: int
)

fun show( p : pattern ) {
  "~" ++ p.elem ++ "#" ++ p.name ++ "." ++  p.classes.join(".") ++
   p.attrselectors.map(fn(e) { "[" ++ e.expression/show ++ "]" }).join
}

fun makePattern( elem : string = "", name : string = "", 
                      classes : list<string> = [], 
                      attrselectors : list<expr> = [],
                      weight : int = ~1) {
  val clss = classes.filter( fn(s) { !s.isEmpty }) 
  // calculate weight according to CSS rules: in order of importance: name, classes, elements
  val w = if (weight >= 0) then weight 
           else (100*(if (name.isEmpty) then 0 else 1) + 10*clss.length + (if (elem.isEmpty) then 0 else 1))
  Pattern(elem.definitionId, name.definitionId, clss, attrselectors, w)
}

pub val emptyRules = Rules([])

pub fun rulesFromMeta( metadata : list<(string,string)> ) : rules {
  val rules = metadata.concat( fn(kv) {
    val (key,value) = kv
    if (key.startsWith("~") || key.startsWith("#") || key.startsWith(".")) then {
      match(key.find(rxPattern)) {
        Nothing -> {
          warning("illegal pattern: " ++ key)
          []
        }
        Just(cap) -> {
          val attrsels = parseAttrSelectors(cap.groups[4])
          val classes  = cap.groups[3].split(".").list
          val pat = makePattern( cap.groups[1], cap.groups[2], classes, attrsels )
          // trace("pattern: " ++ key ++ " -> " ++ pat.show )
          [(pat,value)]
        }
      }
    }
    else []
  })
  Rules(rules)
}
val rxPattern = regex(r#"^(?:~([\w\-:]+))?(?:#([\w\-:]+))?((?:\.(?:[\w\-:]+))*)(?:(\[[^\]]*\])*)$"#)

pub fun matchRules( r : rules, elementName : string, attrs : attrs ) : attrs 
{
  if (!(attrs.common/defaults)) return attrs;
  val name = attrs.name.definitionId
  val elemName = elementName.definitionId
  r.rules.apply( attrs, name, elemName, peano10 )
}

fun apply( rules : list<(pattern,string)>, attrs : attrs, name : string, elemName : string, p : peano ) : attrs {
  match(p) {
    Zero -> attrs
    Succ(p1) -> {
      val (def,rules2) = rules.getMatches( attrs, name, elemName )
      if (def=="") return attrs
      val attrs2 = attrs.mergeDefault(def.parseAttrs)      
      rules2.apply( attrs2, name, elemName, p1 )
    }
  }
}

fun getMatches( rules : list<(pattern,string)>, attrs : attrs, name : string, elemName : string ) : (string,list<(pattern,string)>) {
  var def := []
  val newrules = rules.filterx( fn(rule) {
    val (pat,value) = rule
    if (pat.matches(elemName,name,attrs)) then {
      //trace("matched: weight:" ++ pat.weight.show ++ ": " ++ makePattern(elemName,name,attrs.classes).show ++ " to rule " ++ pat.show ++ ": " ++ value.substr(0,80))
      def := def.insert(pat.weight, value)
      False
    }
    else True
  })
  val fin = def.map(snd).join(" ; ")
  (fin,newrules)
}

// insert a pattern value sorted on weight, from low to high
fun insert( xs : list<(int,string)>, weight :int, value : string ) : list<(int,string)> {
  match(xs) {
    Nil -> [(weight,value)]
    Cons(wv,xx) -> {
      if (wv.fst <= weight)
       then Cons(wv,insert(xx, weight, value))
       else Cons((weight,value),xs)
    }
  }
}

fun matches( pat : pattern, xelem : string, xname : string, attrs : attrs ) : bool {
  (pat.elem.isEmpty || pat.elem == xelem) &&
  (pat.name.isEmpty || pat.name == xname) &&
  (pat.classes.isNil || pat.classes.all( fn(c) { attrs.hasClass(c) } )) &&
  (pat.attrselectors.isNil || pat.attrselectors.all(fn(e) { matchSelector(e,attrs) }))
}

fun matchSelector( e : expr, attrs : attrs ) : bool {
  fun lookup(v,display) {
    String(expandKeyPattern(v,attrs))
  }
  catch { 
    evalExpr(e,lookup).bool 
  } 
  fn(exn) { 
    warning(exn.show)
    False 
  }
}

fun filterx( xs : list<a>, pred : a -> e bool ) : e list<a>
{
  match(xs) {
    Nil -> Nil
    Cons(x,xx) -> if (pred(x)) then Cons(x,xx.filterx(pred)) else xx.filterx(pred)
  }
}


/*
pub fun matchRules( rules : rules, elementName : string, attrs : attrs ) : attrs 
{
  if (!(attrs.common/defaults)) return attrs;
  val extra = ["#" ++ attrs.name.definitionId, "~" ++ elementName.definitionId]
  applyRules(peano10, rules.values, attrs, rules.values.getMatches(attrs,dict(),extra) );
}

fun applyRules(p : peano, defaults : dict<string>, attrs : attrs, dv : (string,dict<bool>) ) : attrs {
  match(p) {
    Zero -> attrs
    Succ(s) -> {
      val (def,visited) = dv
      if (def=="") return attrs
      val attrs2 = attrs.mergeDefault(def.parseAttrs)      
      applyRules( s, defaults, attrs2, defaults.getMatches(attrs2,visited) )
    }
  }
}

fun getMatches( defaults: dict<string>, attrs : attrs, visited : dict<bool> = dict(), extra : list<string> = [] ) : (string, dict<bool>) {
  val keys0 = extra ++ attrs.classes.map( fn(cname) { "." ++ cname.definitionId } ) 
  val keys1 = keys0.filter( fn(key) { visited[key].isNothing } )
  val visited1 = visited ++ keys1.map( fn(key) { (key,True) } ).dict
  val def = keys1.map( fn(key) { defaults[key] }).filter(isJust).map(mbstring).join(" ; ")
  return (def,visited1)
}
*/

pub fun extendAttrs( attrs0 : attrs, attrsStr : string, source : string ) : attrs 
{
  if (attrsStr=="" && source=="") then return attrs0
  val attrsx = attrs0(empty=False, sticky=False, source=source, 
                      text=attrs0.text ++ " ; " ++ attrsStr,
                      classes=[])

  val kvs = attrsStr.joinLines.parseAttributes  // join lines here.
  
  val attrs = kvs.foldl(attrsx) fn(acc:attrs,kv:(string,string,string)) {
    val (name,kwvalue,value) = kv
    val start = name.substr(0,1)
    if (kwvalue=="clear") then {
      if (start==".") then {
        val cname = name.substr(1)
        acc(classes = acc.classes.filter(fn(c) { c != cname }))
      }
      elif (start=="@") then {
        val cname = name.substr(1)
        acc(counters = acc.counters.filter(fn(c) { c.fst != cname }))
      }
      elif (name=="class") then {
        acc(classes = [])
      }
      elif (name=="counters") then {
        acc(counters = [])
      }
      elif (name=="replace" || name=="before" || name=="after") then {
        acc(replacers = [])
      }
      else {
        acc(keyvals = acc.keyvals.filter( fn(k) { k.fst != name }))  
      }
    }
    elif (name=="clear") then {
      Attrs(text=attrsx.text,defaults=False)
    }
    elif (name=="-" || name=="clearnum" || name==".clearnum") then {
      acc( counters=[], label="", replacers=[], 
           classes=["clearnum"] ++ acc.classes.filter(fn(nm) { nm != "clearnum" }) )
    }
    elif (start=="#") then {
      //trace("attrs name: " ++ name ++ ": " ++ value.show)
      acc(name = name.substr(1).definitionId, label = if (value!="") then value else acc.label)
    }  
    elif (start==".") then {
      val cname = name.substr(1)
      if (acc.classes.any( fn(nm) { nm == cname } )) 
       then acc else acc(classes = acc.classes ++ [cname])
    }
    elif (start=="r") then {
      //trace("counter: " ++ name ++ ": " ++ value)
      acc(counters = acc.counters ++ [(name.substr(1), value)] )
    }
    elif (name=="elem") then {
      val ename = value.definitionId
      acc(elem = ename, classes = [ename] ++ acc.classes.filter(fn(nm) { nm != ename }) )
    }
    elif (name=="tex-elem") then {
      acc(texelem = value )
    }
    elif (name=="html-elem") then {
      acc(htmlelem = value )
    }
    elif (name=="id") then {
      //trace("id: " ++ value)
      acc(name = value.definitionId )
    }
    elif (name=="class") then {
      val cname = value.definitionId
      if (acc.classes.any( fn(nm) { nm == cname } )) 
       then acc else acc( classes = acc.classes ++ [cname] )
    }
    elif (name=="label") then {
      acc(label = value)
    }
    elif (name=="sticky") then {
      acc(sticky=value.toBool)
    }
    elif (name=="notag") then {
      acc(notag=value.toBool)
    }
    elif (name=="tag") then {
      acc(notag= !value.toBool)
    }
    elif (name=="line") then {
      match(value.parseInt()) {
        Nothing -> {
          warning("unrecognized line number: line=" ++ value )
          acc
        }
        Just(n) -> acc(lineNo=n)
      }
    }
    elif (name=="replace") then {
      acc(replacers = acc.replacers ++ [value])
    }    
    elif (name=="before") then {
      acc(replacers = acc.replacers ++ [value ++ r"\/&source;"])
    }
    elif (name=="after") then {
      acc(replacers = acc.replacers ++ [r"\/&source;" ++ value])
    }
    elif (name=="input") then {
      val v = kwvalue
      val r = if (v=="pre") then Pre
              elif (v=="raw") then Raw(Nothing)
              elif (v=="texraw") then Raw(Just(FmtTex))
              elif (v=="htmlraw") then Raw(Just(FmtHtml))
              elif (v=="tex") then Tex
              elif (v=="math") then Math
              elif (v=="mathpre") then MathPre
              elif (v=="mathdefs") then MathDefs
              elif (v=="normal") then Markdown()
              elif (v=="markdown") then Markdown()
              elif (v=="htmlonly") then Markdown(Just(FmtHtml))
              elif (v=="texonly") then Markdown(Just(FmtTex))
              else {
                warning( "unrecognized input value: " ++ value)
                Markdown()
              }         
      acc(input=r)
    }
    elif (name=="tight") then {
      acc(tight=value.toBool)
    }
    else {
      //trace("key " ++ name ++ "=" ++ value)
      val cntrs = if (name=="start") then match (value.trim.parseInt) {
                    Just(i) -> acc.counters ++ [(acc.elem ++ "-li",(i - 1).show)] 
                    Nothing -> acc.counters
                  }
                  elif (name=="list-style-type" && acc.elem.bool) then {
                    //trace("list-style-type: @" ++ acc.elem ++ "-li=" ++ value.trim )
                    acc.counters ++ [(acc.elem ++ "-li",value.trim)] 
                  }
                  else acc.counters
      val extra = [parsePageAlign(name,kwvalue)].concat
      acc(keyvals = acc.keyvals.filter(fn(kval) { kval.fst != name && extra.all( fn(kvx) { kvx.fst != kval.fst })}) ++ [(name,value)] ++ extra, counters = cntrs)
    }
  }
  attrs.addClasses(attrs0.classes) // last, so the classes are order for 'elementName'
}

val rxId      = r#"(?:[\.#][\w\.#@\-:]*|[@\-\w][\w\.#@\-]*)"#
val rxQuoted  = r#"(?:'(?:[^\n\\']|\\[\s\S])*'|"(?:[^\n\\"]|\\[\s\S])*")"#
val rxHtmlValue = r"(?:" ++ rxQuoted ++ "|" ++ r#"(?:[^\\"'\s]|\\.)*)"#
val rxCssValue  = r"(?:" ++ rxQuoted ++ "|" ++ r#"(?:&(?:#[xX]?)?[\w\-]+;|[^\\"'\s;,]|\\.)*)"#
val rxHtmlVal = r"(?:\s*=\s*(" ++ rxHtmlValue ++ r"))"
val rxCssVal  = r"(?:\s*:\s*(" ++ rxCssValue ++ r"(?:(?:\s+|\s*(,\s*)+)" ++ rxCssValue ++ r")*))"
val rxAttr    = regex(r"^(" ++ rxId ++ r")(?:" ++ rxHtmlVal ++ "|" ++ rxCssVal ++ ")?")
val rxSep     = regex(r"^(\s+(?:;*(?:$|\s+))?|;(?:$|\s+))")
val rxNoSep   = regex(r"^([^\s;]|;(?!\s))+")

val rxSpaces  = regex(r"\s+")
val rxNoSpaces= regex(r"\\.|" ++ rxQuoted)

fun parsePageAlign( name :string, value: string ) : list<(string,string)> {
  if (name!="page-align") return []
  val placement = if (value=="top") then "t"
                  elif (value=="bottom") then "b"
                  elif (value=="topbottom") then "tb"
                  elif (value=="page") then "p"
                  elif (value=="here") then "h"
                  elif (value=="forcehere") then "h!"
                  elif (value=="inplace") then "H"
                  else ""
  [("tex-float-placement",placement)]                    
}


// Parse an attribute string
val parseAttributes : (string) -> list<(string,string,string)> = smemo(parseAttributesX)

fun parseAttributesX( s : string ) : list<(string,string,string)> 
{
  val res = parseAttributesAcc( s, s, [] )  
  /*
  trace("attributes: " ++ s ++ "\n parsed: " ++ res.map(fn(kvv) {
      val (key,_kwvalue,value) = kvv
      key ++ ": \"" ++ value ++ "\""
    }).join(";")
  )
  */
  res
}

fun parseAttributesAcc( original : string, s : string, acc : list<(string,string,string)> ) : list<(string,string,string)>
{
  if (s=="") return acc.reverse
  match(s.find(rxAttr)) {
    Nothing -> match(s.find(rxSep)) {
      Nothing -> match(s.find(rxNoSep)) {
        Nothing -> {
          warning("invalid attribute: " ++ s ++ "\n  in: " ++ original )
          acc.reverse
        }
        Just(cap) -> {
          warning("invalid attribute: " ++ cap.matched ++ "\n  in: " ++ original )
          parseAttributesAcc( original, s.substr1(cap.next), acc )
        }
      }
      Just(cap) -> {
        parseAttributesAcc( original, s.substr1(cap.next), acc )
      }
    }
    Just(cap) -> {
      val values  = cap.groups.firstMatched(2).trim.splitExclude(rxSpaces,rxNoSpaces)
      val value   = values.filter(legalValue).map(unquote).join(" ") // TODO: we should not unquote here but only as needed!
      val kwvalue = if (values.length==1 && !(value.startsWith("\"") || value.startsWith("'")))
                     then value else ""
      val res     = (cap.groups[1].toLower,kwvalue,value)                     
      parseAttributesAcc( original, s.substr1(cap.next), Cons(res,acc))                     
    }
  }
}

fun legalValue( s : string ) : bool {
  !s.isEmpty && !s.contains(rxCommentValue)
}
val rxCommentValue = regex(r"^/\*(?:[^\\\*]|\\.|\*(?!/))*\*/")

fun unescape( s : string ) : string {
  s
}

fun toBool( s : string ) : bool {
  (s=="" || s=="true")
}

pub fun transformText( attrs : attrs, txt : string, labels : dict<label>, metadata : dict<string> ) : string 
{  
  if (attrs.empty) then return txt
  attrs.replacers.foldl(txt,fn(cur,repl) {
    val res = repl.applyReplacer(cur,attrs,labels,metadata) 
    //trace("replacer '" ++ erepl.substr(0,10) ++ "': " ++ cur ++ " -> " ++ res)
    res
  })
}

fun applyReplacer( repl : string, txt : string, attrs : attrs, labels : dict<label>, metadata : dict<string> ) : string 
{
  fun expand( s : string ) { 
    expandKeys(peanoN,s,txt,attrs,labels,metadata,fn(_,_) {""}) 
  }

  fun checkReplace( rrepl : string ) : string {    
    match(rrepl.find(rxregex)) {
      Nothing -> match(rrepl.find(rxmapping)) {
        Nothing -> rrepl.expand
        Just(mcap) -> {
          regexMapping( mcap.groups[1].expand, mcap.groups[2], txt )
        }
      }
      Just(rcap) -> {
        regexReplacer( rcap.groups[1].expand, rcap.groups[2].expand, rcap.groups[3], txt )
      }
    }
  }

  fun checkCond( crepl : string ) : string {
    if (!crepl.startsWith("@if"))
      then checkReplace(crepl)
      else match (evalCondition(crepl,txt,attrs,labels,metadata)) {
        Null -> txt // missing 'else' -> no replace
        c    -> checkReplace(c.string)
      } 
  }

  checkCond(repl)
}

val rxmapping = regex(r"^//((?:[^\\]|\\.)*)//([gimc]*)$")


val rxregex = regex(r"^/(" ++ rxescaped ++ r"*)/(" ++ rxescaped ++ r"*)/([gimc]*)$")
val rxescaped = r"(?:[^\\/]|\\.)"

fun evalCondition( cond : string, source : string, attrs : attrs, labels : dict<label>, metadata : dict<string> ) : constant {
  fun lookup(v,display) {
    String(expandKeys("&" ++ v ++ ";", source,attrs,labels,metadata))
  }
  val res = evaluate( cond, fn(e) { evalExpr(e,lookup) }, String(""))
  // trace("eval condition: " ++ res.show ++ ": " ++ cond)
  res
}

// remove all grouping from a regular expression
fun ungroup( r : string ) : string {
  r.replaceAll(rxOpenParen, fn(cap) {
    if (cap.groups[1]!="") then "(?:" else cap.matched
    })
}
val rxOpenParen = regex(r"\\.|(\((?!\?))")

val rxEntry      = regex(r"^((?:[^\\/]|\\.)*)/(.*)$")
val rxBar        = regex(r"//")
val rxExcludeBar = regex(r"[^\\/]|\\.|/(?!/)")

// perform a mapping.
fun regexMapping( mapping : string, flags : string, txt : string ) : string 
{
  val entries
    = mapping.splitExclude(rxBar,rxExcludeBar).map( fn(entry) {
        match(entry.find(rxEntry)) {
          Just(ecap) -> {
            (ecap.groups[1],ecap.groups[2])
          }
          Nothing -> {
            warning("illegal mapping: " ++ entry)  
            (entry,"")
          }
        }
      })

  val rexp = regex( entries.map(fn(e){"(" ++ e.fst.ungroup ++ ")"}).join("|"), ignoreCase=flags.contains("i"), multiline=flags.contains("m"))
  val convCase = flags.contains("c")

  fun replaceGroups( cap : matched ) {
    val i = cap.groups.firstMatchedOn(1,entries.length)
    if (i<=0) return ""
    val subst = match(entries.drop(i - 1)) {
      Nil -> cap.matched // should never happen
      Cons(entry) -> {
        val (rx,repl) = entry
        match(cap.matched.find(regex(rx))) // should always match from start to end... 
        {
          Nothing -> cap.matched // should never happen
          Just(rcap) -> {
            // assert: cap.matched == rcap.matched
            repl.replaceAll(rxCaptureGroup, fn(gcap) {
              if (gcap.groups[1] != "\\") then {
                val j = gcap.groups[1].parseInt.maybe(0,id)
                if (convCase)
                 then rcap.groups[j].replaceAll(rxCaseEsc,r"\\$2$1") // escape replacement
                 else rcap.groups[j]  
              }
              else {
                gcap.groups[1]
              }
            })
          }
        }
      }
    }
    if (convCase)
     then subst.caseConvert // unescape replacement
     else subst
  }
  
  val gtxt = if (flags.contains("g")) 
              then txt.replaceAll(rexp,replaceGroups) 
              else txt.replace(rexp,replaceGroups)
  gtxt
}

// "?#caption?/././"
// val rxcond  = regex(r"^/[?](" ++ rxescaped ++ r"+)/(" ++ rxescaped ++ r"*)/([gim]*)$")

fun regexReplacer( rxText : string, rtxt : string, flags : string, txt : string ) 
{
  val rexp = regex(rxText, ignoreCase=flags.contains("i"), multiline=flags.contains("m"))
  val convCase = flags.contains("c")

  fun replaceGroups( cap : matched ) {
    val repl = rtxt.replaceAll( rxCaptureGroup, fn(gcap) {
      if (gcap.groups[1] != "\\") then {
        val i = gcap.groups[1].parseInt.maybe(0,id)
        if (convCase) 
         then cap.groups[i].replaceAll( rxCaseEsc, r"\\$2$1" ) // escape replacement
         else cap.groups[i]   
      }
      else {
        gcap.groups[1]
      }
    })
    if (convCase)
     then repl.caseConvert  // do case conversion (and unescape replacements)
     else repl
  }  
  val gtxt = if (flags.contains("g")) 
              then txt.replaceAll(rexp,replaceGroups) 
              else txt.replace(rexp,replaceGroups)
  //trace("replace (" ++ rxText.substr(0,20) ++ "): '" ++ txt ++ "' to '" ++ gtxt ++ "'")    
  gtxt
}

val rxCaptureGroup = regex(r"\\([\d\\])")
val rxCaseEsc = regex(r"\\((\\)|[/ulULE])")
//val rxRegEsc  = regex(r"\\((\\)|[/])")

fun caseConvert( txt : string ) : string {
  txt.replaceAll(regex(r"\\([\\/E])|\\([ul])(.)|\\([UL])([\s\S]*?)(\\E|$)"), fn(cap) {
    if (cap.groups.matchedOn(1)) then {
      cap.groups[1] // unescape
    }
    elif (cap.groups.matchedOn(2)) then {
      if (cap.groups[2]=="u") then cap.groups[3].toUpper else cap.groups[3].toLower      
    }
    elif (cap.groups.matchedOn(4)) then {
      if (cap.groups[4]=="U") then cap.groups[5].toUpper else cap.groups[5].toLower      
    }
    else cap.matched
  }) 
}


pub fun expand( attrs : attrs, metadata : dict<string>, labels : dict<label> = dict() ) : attrs {
  if (attrs.empty) return attrs 

  attrs( keyvals = attrs.keyvals.map fn(kv) {
    (kv.fst, kv.snd.expandKeys( attrs.source, attrs, labels, metadata ))
  })
}

pub fun expandKeys( txt : string, metadata : dict<string> ) : string {  
  expandKeys(peanoN,txt,"",attrsNone,dict(),metadata)
}

pub fun expandKeyName( name : string, labels : dict<label>, metadata : dict<string> ) : string {  
  expandKeys(peanoN,"&" ++ name ++ ";","",attrsNone,labels,metadata)
}

pub fun expandKeys( txt : string, source : string, 
                            attrs : attrs, 
                            labels : dict<label>, metadata : dict<string> ) : string {
  expandKeys(peanoN,txt,source,attrs,labels,metadata)
}

fun expandKeyPattern( name : string, attrs : attrs ) : string {
  expandKeys(peanoN,"&" ++ name ++ ";",attrs.source,attrs,dict(), dict(), ignoreNotFound)
} 

// expand keys in a string
fun expandKeys( p0 : peano, txt : string, source : string, 
                            attrs : attrs, 
                            labels : dict<label>, metadata : dict<string>, 
                            notFound : (string,string) -> string = keyNotFound ) : string 
{  
  if (txt=="") then return txt
  match(p0) {
    Zero -> txt
    Succ(p) -> {
      txt.replaceAll(rxkey) fn(cap) {
        val rawkey = cap.groups[1]
        val key = rawkey.normalizeId 
        if (rawkey=="") then cap.matched  // no key was matched
        elif (rawkey=="&") then "&"       // special in replacements
        elif (key=="label" && !(attrs.empty)) then attrs.label
        elif (key=="id" && !(attrs.empty)) then attrs.name 
        elif (key=="class" && !(attrs.empty)) then attrs.classes.join(" ") 
        elif (key=="source" && !(attrs.empty)) then source // attrs.source 
        else match (attrs.keyvals.find(fn(kv){ kv.fst == key })) {
          Just(kv) -> {
            if (txt == kv.snd) then kv.snd
             else expandKeys(p,kv.snd,source,attrs,dict(),metadata,notFound)                
          }
          Nothing  -> match(labels[key]) {
            Just(label) -> label.labelText // already expanded
            Nothing -> match(metadata[key]) {
              Just(value) -> {
                // semi-static scoping: clear out labels, but keep attributes
                expandKeys(p,value,source,attrs,dict(),metadata,notFound)
                // todo? full static scoping: clear out attributes and labels..
                //expandKeys(p,value,"",attrsNone,dict(),metadata,notFound)              
              }
              Nothing -> match(entityNameAsNum(rawkey)) {
                Just(value) -> value
                Nothing     -> notFound(key,cap.matched)
                //entityNameToNum(key)
              }
            }
          }
        }
      }      
    }
  }
}
val rxkey = regex(r"\\&|(?:\\/)?&([\w\-:]*|&);(\\/)?") 

fun keyNotFound( key: string, matched : string ) : string {
  warning( "undefined key: " ++ key)
  matched
}

fun ignoreNotFound( key: string, matched : string ) : string {
  matched
}


extern smemo( f : (string) -> e a ) : (string -> e a) {
  js inline "((fn(){ var dict={}; return (fn(s) { if (dict[s]===undefined) dict[s] = (#1)(s); return dict[s]; }); })())"
}

