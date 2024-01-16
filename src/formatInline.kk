/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// The parsing and formatting of _inline_ elements (i.e. emphasis, links, etc.)
module formatInline

import std/data/dict
import std/text/regex
// import std/crypto
import std/os/path   // extname
import common
import attributes
import inline
import htmlFormatter  // htmlEscape
import entity
import hilite // inlineMode
import codeAlign

/* --------------------------------------
  Inline grammar
---------------------------------------- */
alias inlineRule = rule<string,inlineContext>

val normal       = r#"(?:[^`*_\\~&<>\^#\$"'\[!\-\. \+@]| (?! \n| *[\[\-\+!@])|-(?![@\-])|\+(?!@)|\.(?!\.\.)|!(?![@\[]))"#
val normalbench  = r#"(?:[^"'`*_\\~&<>\^#\$\[!]| (?! \n))"#

//val attrs    = r"\{:?((?:[^\}\n]|\\\})*)\}"
val attrs      = r#"\{:?((?:[^\\'"\}\n]|\\[.\n]|'[^']*'|"[^"]*")*)\}"#  // allow optional colon for maraku compat

val linkhref = r#"\s*<?([^\s>)]*)>?(?:\s+['"](.*?)['"])?\s*"#
val xlinkid   = r"((?:[^\[\]\n]|\[[^\]\n]*\])*)"
val linktxt  = r"\[(?!\^)((?:\[(?:[^\[\]]|\[(?:[^\[\]]|\[[^\]]*\])*\])*\]|\\.|[^\\\]]|\](?=[^\[{]*\]))*)\]"
val linkreg  = linktxt + r"((?:\(" + linkhref + r"\)|\s*\[" + xlinkid + r"\])?(?:" + attrs + r")?)"

pub val rxLink = regex(linkreg)

fun inlineCoreGrammar( fmt : formatter ) : grammar<string,inlineContext>
  [
    Rule("itext",     regex(r"^" + normal + "+"), inlineNormal ),

    //Rule("iquotes",   regex(r"^(?:'(?!\s|s\b|re\b)((?:[^\\'`\$\[<]|\\.|'[a-zA-Z])*)'(?![a-zA-Z])|"((?:[^\\"`\$\[<]|\\.)*)")"), inlineQuotes ),
    Rule("iquotes",   regex(r#"^(?:'(?!\s|s\b|re\b)((?:[^\\']|\\.|'[a-zA-Z])*)'(?![a-zA-Z])|"((?:[^\\"]|\\.)*)")"#), inlineQuotes ),
    Rule("icode",     regex(r"^(`+)((?:[^`]|(?!\1)`)*)\1(?:" + attrs + ")?"), inlineCode ),
    Rule("ilink",     regex(r"^([\n ]*)" + linkreg), inlineLink ),
    Rule("iemph*",    regex(r"^(\*)((?:[^\\*]|\\.)+)\*"), inlineEmph),

    Rule("iimg",      regex(r"^()!" + linkreg), inlineImg ),
    Rule("ifootnote", regex(r"^\[\^" + xlinkid + r"\]"), inlineFootnote ),
    //Rule("iguil",     regex(r"^<<((?:[^\\>]|>(?!>)|\\.)*)>>"), inlineQuotes ),
    Rule("iguil",     regex(r"^<<((?:[^\\>]|>(?!>)|\\.)*)>>"), inlineQuotes ),
    Rule("iautolink", regex(r"^<([^/\s>][^\s>]*?(@|:/)[^\s>]+?)>(?:" + attrs + ")?"), inlineAutoLink ),
    Rule("istrong_",  regex(r"^(__)((?:[^\\]|\\.)+?)__(?!_)"), inlineStrong),
    Rule("istrong*",  regex(r"^(\*\*)((?:[^\\]|\\.)+?)\*\*(?!\*)"), inlineStrong),
    Rule("iemph_",    regex(r"^\b(_)((?:[^\\_]|\\.)+)_\b"), inlineEmph),
    Rule("idel",      regex(r"^~~(?=\S)([\s\S]*?\S)~~"), inlineDel ),
    Rule("isub",      regex(r"^~((?:[^~\\\n\r]|\\.)+)~"), inlineSub ),
    Rule("isup",      regex(r"^\^((?:[^\^\\\n\r]|\\.)+)\^"), inlineSup ),
    Rule("itagcode",  regex(r#"^(<code\b(?:"[^"]*"|'[^']*'|[^'">])*?>)([\s\S]*?)(</code>)"#), inlineTagCode ),
    Rule("itag",      regex(r#"^<(?:!--[\s\S]*?-->|/?\w+\b(?:"[^"]*"|'[^']*'|[^'">])*?>)"#), inlineTag ),
    Rule("ientity",   regex(r"^&(#?[\w\-:]*);"), inlineEntity ),
    //Rule("ilabel",    regex(r"^(#[a-zA-Z][\w\-:]*);?"), inlineLabel ),

    Rule("idashes",   regex(r"^--(-)?"), inlineDashes ),
    Rule("ielipsis",  regex(r"^\.\.\."), inlineDots ),

    Rule("texinline", regex(r"^\$(?!\$)((?:[^\\\$]|\\[\s\S])+)\$(?:" + attrs + ")?"), inlineMath ),
    Rule("texblock1", regex(r"^\$\$( *\n(?:[^\\\$]|\\[\s\S]|\$[^\$])*)\$\$"), inlineMathBlock ),
    Rule("texblock2", regex(r"^\\\[( *\n(?:[^\\]|\\[^\]])*)\\\]"), inlineMathBlock ),

    Rule("textcite",  regex(r"^([\n ]*)(([\-+!]?)r" + rxCitename + ")"), inlineCite ),

    Rule("ibr",       regex(r"^  \n(?!\s*$)"), inlineBreak ),
    Rule("iescape",   regex(r"^\\([^a-zA-Z0-9])"), inlineEscape ),

    Rule("other",     regex(r"^[\s\S]"), inlineOther )
  ]

val benchGrammar
  = inlineCoreGrammar(FmtHtml).stripFancyRules

fun stripFancyRules( g : grammar<string,inlineContext> ) : grammar<string,inlineContext> {
  g.ruleReplace(True, Rule("itext", regex("^" + normalbench + "+"), inlineNormal ))
   .ruleReplace(True, Rule("iquotes", regex(r#"^["']"#), inlineQuot ))
   .ruleRemove(True,["idashes","ielipsis","tex","iguil","textcite"])
}

pub fun inlineGrammar( fmt : formatter, bench : bool = False ) {
  if (bench) then benchGrammar else inlineCoreGrammar(fmt)
  /* for gfm style line breaks */
  /*
  inlineCoreGrammar
   .ruleReplace( breaks, Rule("itext", regex(r"^(?:[^\n" + special + "])+"), inlineNormal ))
   .ruleReplace( breaks, Rule("ibr",   regex(r"^\n(?!\s*$)"), inlineBreak ))
  */
}


/* --------------------------------------
 Inline grammar funs
---------------------------------------- */

fun inlineBreak( cap : matched, contxt ) {
  match(contxt.fmt) {
    FmtHtml -> contxt.fmtText("<br>\n")
    _ -> contxt.fmtCmd("br","")
  }
}

fun inlineEntity( cap : matched, contxt : inlineContext ) : string {
  val key = cap.groups[1]
  if (key.startsWith("#")) // character code
   then contxt.fmtText(cap.matched)
   else {
    val txt = expandKeyName(key,contxt.labels,contxt.metadata)
    if (txt==cap.matched)             // prevent obvious infinite loop
     then contxt.fmtText(txt)
     else contxt.formatInline(txt)   // format the expansion
  }
}

fun inlineNormal( cap : matched, contxt : inlineContext ) : string {
  contxt.fmtText(cap.matched)
}

fun inlineMath( cap : matched, contxt : inlineContext ) : string {
  val attrs = cap.groups[2].parseAttrs("math-inline");
  //val attrsd = contxt.defaults.matchRules("math-inline",attrs)
  //contxt.fmtMath(False,cap.groups[1],attrsd)
  contxt.fmtSpan( cap.groups[1], attrs ); // can be taken over by the user
}


fun inlineMathBlock( cap : matched, contxt : inlineContext ) : string {
  val attrsd = contxt.defaults.matchRules("math-display",attrsNone)
  contxt.fmtMath(True,cap.groups[1],attrsd)
}

pub fun fmtMath( contxt : inlineContext, isDisplay : bool, txt0 : string, attrs : attrs = attrsNone, lineInfo : string = "" ) : string {
  val (kind,left,right,rightx) =
    if (attrs.hasClass("snippet"))
     then (if (isDisplay) then "Display" else "Inline","","","")
    elif (isDisplay)
     then ("Display","\\[" + (if (attrs.name.isEmpty) then "" else "\\label{" + attrs.name + "}"),"\n\\]","%mdk\n")  // add newline because of comments in latex (and we do use trimLines on the content)
     else ("Inline","$","$","")
  val lkind  = kind.toLower
  val class  = "math-" + lkind
  val attrsd = contxt.applyDefaults("span",attrs.addClass(class))
  val mode   = if (attrsd.hasBoolKey("math-full") || attrsd.hasBoolKey("snippet-needpdf") || attrsd.hasBoolKey("math-needpdf")) then Full else Plain
  //ptxt = if (attrs.hasClass("mathpre")) then mathPre(txt) else txt
  val txt    = txt0.trimLines
  val texcmd = if (kind=="Inline")
                then contxt.fmtMathCmd("span", left+lineInfo+txt+right+rightx, attrsd)
                else contxt.fmtMathEnv("div",  left+lineInfo+txt+right+rightx, attrsd)
  match(contxt.fmt) {
    FmtTex -> texcmd
    _      -> {
      val mtxt = left + txt.escapeMath(contxt.fmt) + right
      val mcmd = contxt.fmtCmd("span",contxt.fmtText(mtxt),attrsd)
      if (contxt.mathStatic || mode.isFull /* never use mathjax for full math */) then {
        val digest = md5(txt)
        log("math-" + mode.show,
              r"\begin{md" + kind + "Snippet}[" + digest + "]%mdk\n" +
                texcmd + "\\end{md" + kind + "Snippet}%mdk")
        //trace("math: " + digest)
        match(contxt.mathinfos[digest]) {
          Nothing  -> contxt.fmtCmd("span",mcmd,attrsNone.addClass("math-rendering").addKeyval("html-title","Rendering math..."))
          Just(mi) -> contxt.fmtMathImg(mi,txt,mtxt,attrsd)
        }
      }
      else mcmd
    }
  }
}

pub fun fmtMathImg( contxt : inlineContext, mi : mathinfo, txt : string, mtxt : string, attrs : attrs ) {
  val scale = match(attrs.hasKey("math-scale")) {
            Just(value) -> value.parseInt.maybe(100,id).double / 100.0
            Nothing     -> 1.0
          }
  val baseline = match(attrs.hasKey("math-baseline")) {
                   Just(value) -> value.parseInt.maybe(0,id).double
                   Nothing     -> 0.0
                 }
  // Depth and height are in _pt_. Since we assume that the math has been
  // type set with a 10pt font, we divide by 10 to get the units in _em_.
  // This has the advantage that it will scale automatically if the user
  // selected a larger display font.
  // We substract bboxFuzz from the depth to adjust for extra bbox spaces
  // when extracting images.
  val fontsize = 10.0
  val valign   = baseline - ( (scale * (mi.depth + mi.bboxFuzz))  / fontsize)
  val height   = (scale * mi.height / fontsize)
  val width    = (scale * mi.width / fontsize)
  val xattrs0  = if (valign== 0.0) then attrs
                  else attrs.addKeyvalIfNotExist("vertical-align",valign.showFixed(4) + "em")
  val xattrs1  = xattrs0.addClass(
                  if (mi.imageData.startsWith(svgPrefix) || mi.imageName.extname.toLower == ".svg")
                    then "math-render-svg" else "math-render-png")
  val xattrs  = xattrs1.addKeyvalIfNotExist("height",height.showFixed(4) + "em").addClass("math")
  val wattrs  = xattrs.addKeyvalIfNotExist("width", width.showFixed(4) + "em")

  if (height<=0.0 || width<=0.0) then {
    // empty image
    contxt.fmtCmd("span","",wattrs.addKeyval("html-alt",mtxt))
  }
  elif (mi.imageData.startsWith(svgPrefix)) then {
    // embedded svg: format it inline with the attributes spliced in
    val svg = mi.imageData.substr(svgPrefix.length)
    contxt.fmtHtmlSvg( svg, wattrs, mtxt )
  }
  else {
    // png, or svg image file, emit an img element
    val src = if (mi.imageData!="") then mi.imageData else mi.imageName
    contxt.fmtLink(True,Link(src,"",xattrs),mtxt)
  }
}

val svgPrefix = "data:image/svg+xml;charset=utf8,"

fun escapeMath( txt : string, fmt : formatter ) : string {
  match(fmt) {
    FmtHtml -> txt.htmlEscape
    FmtTex  -> txt
  }
}


fun inlineQuot( cap : matched, contxt ) : string {
  contxt.formatInline(if (cap.matched=="\"") then "&quot;" else "&apos;")
}

fun inlineStrong( cap : matched, contxt ) : string {
  val tag = if (contxt.starBold && cap.matched.startsWith("_")) then "em" else "strong"
  val class = tag + (if (cap.matched.startsWith("*")) then "-star" else "-low") + cap.groups[1].length.show
  val attrs = contxt.defaults.matchRules( tag, attrsNone.addClass(class) )
  contxt.fmtCmd(tag, formatInline(contxt,cap.groups[2]), attrs)
}

fun inlineEmph( cap : matched, contxt ) : string {
  val tag = if (contxt.starBold && cap.matched.startsWith("*")) then "strong" else "em"
  val class = tag + (if (cap.matched.startsWith("*")) then "-star" else "-low") + cap.groups[1].length.show
  val attrs = contxt.defaults.matchRules( tag, attrsNone.addClass(class) )
  contxt.fmtCmd(tag, formatInline(contxt,cap.groups[2]), attrs )
}

fun inlineSup( cap : matched, contxt ) : string {
  contxt.fmtCmd("sup", formatInline(contxt,cap.groups[1]), contxt.defaults.matchRules("sup",attrsNone))
}

fun inlineSub( cap : matched, contxt ) : string {
  contxt.fmtCmd("sub", formatInline(contxt,cap.groups[1]), contxt.defaults.matchRules("sub",attrsNone))
}

fun inlineDel( cap : matched, contxt ) : string {
  contxt.fmtCmd("del", formatInline(contxt,cap.groups[1]), contxt.defaults.matchRules("del",attrsNone))
}

fun inlineTag( cap : matched, contxt : inlineContext ) : string {
  inlineTagX(cap.matched,contxt)
}

fun inlineTagX( tag : string, contxt : inlineContext ) : string {
  if (contxt.sanitize || !(contxt.fmt.isFmtHtml))
   then ""
   else tag
}

fun inlineTagCode( cap : matched, contxt : inlineContext ) : string {
  // TODO: we do not process fully inside <code> for now; remove this later
  // when koka documentation generates markdown instead of html.
  val icontext = contxt.copy(grammar = contxt.grammar.stripFancyRules)
  inlineTagX(cap.groups[1],contxt) +
   icontxt.formatInline(cap.groups[2]) +
   inlineTagX(cap.groups[3],contxt)
}

fun inlineCode( cap : matched, contxt ) : string {
  val txt0 = cap.groups[2]
  val txt1 = if (txt0.startsWith(" `")) then txt0.substr(1) else txt0
  val txt  = if (txt0.endsWith("` ")) then txt1.substr(0,txt1.length - 1) else txt1
  val attrs = if (cap.groups.matchedOn(3))
               then cap.groups[3].parseAttrs("code") else attrsNone
  if (contxt.bench)
   then contxt.fmtCode( "",txt,attrs)
   else contxt.fmtSpan( txt,  // can be overridden by the user
          attrs.addClasses(["code","code" + cap.groups[1].length.show]))
}

pub fun fmtCode( contxt : inlineContext, env0 : string, txt : string, attrs0 : attrs = attrsNone ) : string {
  val env = if (env0=="") then "code" else env0
  //trace("code: " + env + ": " + attrs0.show)
  val lang   = attrs0.hasKey("language").maybe("",id)
  val attrs1 = if (lang=="") then attrs0 else attrs0.addClasses(["language-" + lang, "lang-"+lang, lang])
  val attrs  = contxt.formatDefaults(attrs1,env)
  //trace("code: " + env + ": " + attrs2.show)

  val cattrs = match(attrs.hasKey("data-line-first")) {
                 Nothing -> attrsNone
                 Just(v) -> attrsNone.addKeyval("data-line",v)
                }
  val cattrsTable  = if (attrs.hasBoolKey("pretty-breakable"))
                 then cattrs.addKeyvals([("pretty-breakable","true"),("tex-longtable",attrs.lookupKey("tex-longtable","longtable"))])
                 else cattrs

  val pretty = attrs.hasClass("pretty")
  val plain0 = (lang=="" || !(contxt.highlight) || attrs.hasClass("plain") || attrs.hasClass("prettyprint"))
  val plain = if (plain0) then plain0 else {
    if (canHilite(lang)) then False else {
      warning("unknown language: " + lang)
      True
    }
  }


  fun colorize( code : string, mode : maybe<hilitemode> ) : (string,maybe<hilitemode>) {
    if (plain)
     then (code, mode)
     else match(code.hilitePartial(lang,mode)) {
            Nothing         -> (code,mode)
            Just((hl,next)) -> (hl,Just(next))
          }
  }

  fun colorToken( classes : list<string>, content : string ) : string {
    if (plain || classes.isNil) then content else {
      val pclasses = if (!pretty) then classes else Cons("ptoken",classes.filter(fn(cname) { cname!="token" } ))
      val tokAttrs = contxt.formatDefaults( attrsNone(elem="span").addClasses(pclasses) )
      contxt.fmtCodeToken(pclasses,content,lang,tokAttrs)
    }
  }

  fun colorCode( content : string, startline : bool ) : string {
    content.replaceAll("<br>","\n").replaceAll(rxEndSpaces," ").replaceAll( rxTokens, fn(cap) {
      val nl = (pretty && ((cap.index==0 && startline) || (content.substr(cap.index - 1,1) == "\n")))
      if (cap.groups[2].bool) then {  // token span
        val classes = cap.groups[2].split(" ").list
        colorToken( classes, contxt.fmtCodePlain( cap.groups[3].htmlUnescape, nl ) )
      }
      elif (cap.groups[4].bool) then { // unknown tag
        ""
      }
      else { // literal
        contxt.fmtCodePlain( cap.matched.htmlUnescape, nl )
      }
    });
  }

  fun codeEscape( code : string ) : string {
    contxt.fmtCodeEscaped(txt,colorize,colorToken,attrs).fst   // possibly tokenize with colors, and process escapes
  }

  fun codeUnescape( ecode : string, col : int ) : string {
    fmtCodeUnescape( ecode, fn(s,startLine) {
      if (plain) then contxt.fmtCodePlain(s) else colorCode(s, startLine /* col==0 */)
    })
  }


  val pattrs0 = if (plain) then attrs else attrs.addClass("colorized")
  val pattrs = contxt.formatDefaults(pattrs0)
  val content
    = if (pretty && env != "code" ) then {
        val ct = codeAlign(codeEscape(txt),contxt.prettyAlign).map( codeUnescape )
        contxt.fmtCodeTable(ct,cattrsTable)
      }
      else codeUnescape(codeEscape(txt), 0) // todo: optimize the escape/unescape path?


  if (env=="code")
   then contxt.fmtCmd("code", content, pattrs.mergeDefault(cattrs))
   else contxt.fmtEnv(env, contxt.fmtCmd( if (contxt.fmt==FmtTex) then "precode" else "code", content, cattrs), pattrs)
}

val rxEndSpaces = regex(r"  +$",multiline=True)
val rxTokens = regex( r"([^<>]+)|" + rxToken + "|(<([^>]*)>)|(.)", ignoreCase=True)
val rxToken  = r#"(?:<span\s+.*?\bclass=['"]?([^"']+)['"]?[^>]*>([\s\S]*?)</span>)"#

fun htmlUnescape( s : string ) : string {
  s.replaceAll( rxEntity, fn(cap) {
    match(entityToNum(cap.groups[1])) {
      Nothing -> cap.matched;
      Just(i) -> string(1,i.char)
    }
  })
}
val rxEntity = regex( r"&(#[xX]\d+|\w+);" )

fun fmtCodeUnescape( txt : string, fmt : (string,bool) -> string ) : string {
  fun unspan(caps : list<matched>, i : int ) {
    match(caps) {
      Nil -> txt.substr(i).fmt(i==0)
      Cons(cap,rest) -> {
        txt.substr(i,cap.index - i).fmt(i==0) + cap.groups[1] + unspan(rest, cap.next)
      }
    }
  }
  val caps = txt.findAll(rxEscaped).list
  unspan(caps,0)
}
val rxEscaped = regex(r"<ESCAPED\b[^>]*>([\s\S]*?)</ESCAPED>")

fun fmtCodeEscaped( contxt : inlineContext, txt : string, format : (string,maybe<a>) -> (string,maybe<a>),
                         formatToken : (list<string>,string) -> string,
                         attrs : attrs = attrsNone, st : maybe<a> = Nothing ) : (string,maybe<a>) {
  if (attrs.hasClass("noescape")) return format(txt,st)

  fun codeEscape( src : string, st0 : maybe<_a> ) : (string,maybe<_a>) {
    match( src.find(rxCodeEscaped)) {
      Nothing   -> format(src,st0)
      Just(cap) -> {
        val (fmt1,st1) = format(src.substr(0,cap.index),st0)
        val subcode    = cap.groups[2].replaceAll(regex(r"\\([^\w])"), "$1")
        val width      = if (cap.groups.matchedOn(1)) then cap.groups[1].parseInt.maybe(1,id)
                         elif (cap.groups.matchedOn(2)) then subcode.length
                         else 1
        val (fmt2,st2) = format(subcode,st1) // for colorization, use the provided substitution
        val classes2   = match(fmt2.find(rxClass)) {
                           Just(ccap) -> (ccap.groups[1] + ccap.groups[2] + ccap.groups[3]).split(" ").list
                           Nothing    -> []
                         }

        val innerEsc   = contxt.fmtCmd("span", contxt.formatInline(cap.groups[3]),
                           contxt.formatDefaults(attrsNone.addClass( "code-escaped" )))
        val escaped    = formatToken(classes2,innerEsc).replaceAll("%mdk\n","{}")
        val fmt3       = "<ESCAPED width=" + width.show + ">" + escaped + "</ESCAPED>"

        val (fmt4,st3) = codeEscape(src.substr1(cap.next),st2)
        (fmt1 + fmt3 + fmt4, st3)
      }
    }
  }

  codeEscape(txt,st)
}
//val rxCodeEscaped = regex(r"\\\((?:(\d+):)?((?:[^\\\r\n]|\\\n|\\[^\)])*)\\\)")
val rxCodeEscaped = regex(r"\\\((?:(\d+):)?(?:((?:[^\\\|]|\\[^\)])*)\|)?((?:[^\\\r\n]|\\\n|\\[^\)])*)\\\)")
val rxClass       = regex(r#"^<span\s+class=(?:"([^"]*)"|'([^']*)'|([^\s\&<>]+))\s*>"#,ignoreCase=True)

fun escapeTexPre( txt : string ) : string {
  txt.replaceAll(regex(r"\$"),r"$\text{\tt\textdollar}$")
     .replaceAll(regex(r"\|"),r"$\text{\tt\textbar}$")
}

fun inlineDashes( cap : matched, contxt ) : string {
  contxt.formatInline(if (cap.groups[1] != "") then "&mdash;" else "&ndash;")
}


fun inlineQuotes( cap : matched, contxt : inlineContext ) : string {
  val quote = cap.matched.substr(0,1)
  if (quote == "'")
   then contxt.formatInline("&lsquo;" + cap.groups[1] + "&rsquo;")
  elif (quote=="<")
   then contxt.formatInline("&laquo;" + cap.groups[1] + "&raquo;")
   else contxt.formatInline("&ldquo;" + cap.groups[2] + "&rdquo;")
}

fun inlineDots( cap : matched, contxt ) : string {
  contxt.formatInline("&hellip;")
}

fun inlineOther( cap : matched, contxt ) : string {
  //trace("other: " + cap.matched)
  contxt.fmtEscape(cap.matched)
}

fun inlineEscape( cap : matched, contxt : inlineContext ) : string {
  val txt = cap.groups[1]
  if (txt==" ") then contxt.formatInline("&nbsp;")
  elif (txt=="\n") then inlineBreak(cap,contxt)
  elif (txt=="/") then ""
  elif (contxt.sanitize) then contxt.fmtEscape(txt)
  else contxt.fmtText(txt)
}

pub fun hypenateUrl( url : string ) : string {
  url.replaceAll(rxPostHyphen,"$1&#8203;").replaceAll("%","&#8203;%")
}
val rxPostHyphen = regex(r"([\-\._/\?#\[\]@!$&'\(\)\*\+,;=]+)")


fun inlineAutoLink( cap : matched, contxt : inlineContext ) : string {
  val attrs  = if (cap.groups.matchedOn(3)) then contxt.formatAttrs(cap.groups[3].parseAttrs) else attrsNone
  val attrsd = contxt.defaults.matchRules( "a", attrs.addClass("texturl"))
  if (cap.groups[2] == "r") then {
    val text = cap.groups[1].replace(regex(r"^mailto:"),"")
    val url  = "mailto:" + text
    contxt.fmtLink(False,newLink(url,linkattrs=attrsd,bench=contxt.bench),contxt.fmtEscape(text.hypenateUrl))
  }
  else {
    contxt.fmtLink(False,newLink(cap.groups[1],linkattrs=attrsd,bench=contxt.bench),contxt.fmtEscape(cap.groups[1].hypenateUrl))
  }
}

fun inlineLink( cap : matched, contxt : inlineContext ) : string {
  inlineLinkEx(False,cap,contxt)
}

fun inlineImg( cap : matched, contxt : inlineContext ) : string {
  inlineLinkEx(True,cap,contxt)
}

fun inlineLinkEx( isImage : bool, cap : matched, contxt : inlineContext ) : string {
  // cap.groups = 1:optional spaces, 2:txt, 3:everything after it,
  //               AND 4:href, 5:href-title, OR 6: linkid, AND 7:span attributes
  val attrs  = if (cap.groups.matchedOn(7)) then contxt.formatAttrs(cap.groups[7].parseAttrs) else attrsNone
  //val attrs   = contxt.applyDefaults(if (isImage) then "img" else "a", attrs0)

  val nbsp = if (cap.groups[1] != "" && cap.groups[1].list.all(fn(c){c==' '}))
              then contxt.fmtText("&nbsp;") else cap.groups[1]
  if (cap.groups.matchedOn(4)) then {
    // direct url link:  [text](url title){attrs}
    val attrsd = contxt.defaults.matchRules( if (isImage) then "img" else "a", attrs)
    nbsp + contxt.fmtLink(isImage, newLink(cap.groups[4],cap.groups[5],attrsd,bench=contxt.bench),
                                 contxt.formatInline(cap.groups[2]))
  }
  elif (contxt.bench || cap.groups.matchedOn(6)) then {
    // [text][ref]{attrs}
    inlineLinkRef(isImage, cap.groups[1], nbsp, cap.groups[2], cap.groups[3], cap.groups[6], attrs, contxt )
  }
  else {
    // [text]{attrs}
    inlineLinkNoRef(isImage, cap.groups[1], nbsp, cap.groups[2], cap.groups[3], attrs, contxt)
  }
}

struct cite(
  name    : string,
  pre     : string,
  post    : string,
  modifier: string,
  number  : string,
  year    : string,
  authors : string,
  ordinal : int
)

fun newCite( contxt : inlineContext, name : string, pre : string, post : string, modifier : string,
                  citeLabel : string, attrs : attrs )
{
  val numlab = match(contxt.labels[name]) {
                 Nothing   -> "?"
                 Just(lbl) -> lbl.labelText
               }
  val ordinal = match(numlab.find(rxDigits)) {
                  Just(cap) -> cap.matched.parseInt.maybe(0,id)
                  Nothing   -> 0
                }
  //trace("citeLabel: " + name + ": " + citeLabel)
  val authors = if (modifier=="+" && attrs.hasKey("cite-authors-long").bool)
                 then attrs.lookupKey("cite-authors-long","")
                 else attrs.lookupKey("cite-authors","")
  val year    = attrs.lookupKey("cite-year", "")
  val number  = if (citeLabel=="") then numlab else citeLabel

  match (post.find(rxCommaAt)) {
    Nothing -> ()
    Just(cap) -> warning( "citations need to be semi-colon separated: "  + cap.matched )
  }

  fun wrap( s, wattrs ) {
    if (s.isEmpty) then "" else "[" + s + "]{" + wattrs + "}"
  }

  Cite( name, pre, post, modifier,
        wrap(number,".cite-number"),
        wrap(if (year=="") then number else year,".cite-year"),
        wrap(authors,".cite-authors"),
        ordinal )
}
val rxCommaAt = regex(r",\s*[+!-]?@([\w-:]+)")
val rxDigits = regex(r"\d+")

fun inlineLinkNoRef( isImage:bool, spaces : string, nbsp : string, txt : string, after : string, attrs : attrs, contxt : inlineContext ) : string
{
  val citationss
            = if (contxt.bench || !(txt.contains("r"))) then Nil
                else txt.splitExclude(rxCiteSep,rxCiteSepExclude).map(fn(elem) {
                        match (elem.find(rxCitation)) {
                          Nothing -> []
                          Just(cap) -> {
                            log("aux",r"\citation{" + cap.groups[3] + "}")
                            val lab = ("r" + cap.groups[3]).definitionId
                            match(contxt.labels[lab]) {
                              Just(lbl) -> {  // | lbl.element == "bibitem"
                                [contxt.newCite(lab.substr(1),cap.groups[1],cap.groups[4],cap.groups[2],
                                                  lbl.labelText, lbl.labelAttrs)]
                              }
                              Nothing -> {
                                warning( "missing citation: r" + cap.groups[3] )
                                []
                              }
                            }
                          }
                        }
                      })

  //trace("citations: " + citationss.concat.join("-"))
  if (citationss.isCons && citationss.all(isCons)) then {
    // Citations link: set defaults as "citations" block
    val attrsc = attrs.addKeyval("target-element","bibitem")
    val attrsd = contxt.defaults.matchRules("citations",attrsc)
    contxt.fmtCite(nbsp,citationss.concat,attrsd)
  }
  else {
    inlineLinkRef( isImage, spaces, nbsp, txt, after, "", attrs, contxt )
  }
}
val rxCiteSep         = regex(r"\s*[;]\s*")
val rxCiteSepExclude  = regex(r"[^\\;\s]|\\.")
val rxCitation        = regex(r"^((?:[^\w\\@+!-]|[+!-](?!@)|\\.|\w(?![+!-]?@))*)(?:([+!-]?)r" + rxCitename + r")([\s\S]*)$")
val rxCitename        = r"(\w(?:[\w]|[:\-\.]\w)*)"

fun inlineCite( cap : matched, contxt : inlineContext ) : string {
  log("aux",r"\citation{" + cap.groups[4] + "}")
  match(contxt.labels[("r" + cap.groups[4]).definitionId]) {
    Just(_) -> contxt.formatInline(cap.groups[1] + "[" + cap.groups[2] + "]{.textual" +
                                      (if (cap.groups[3]=="-") then " .free" else "") + "}")
    Nothing -> {
      if (cap.groups[1] != "") then {
        warning( "possibly missing citation: " + cap.groups[2])
      }
      contxt.fmtText(cap.matched)
    }
  }
}

fun inlineLinkRef( isImage : bool, spaces : string, nbsp : string, txt : string, after : string, ref : string,
                          attrs : attrs, contxt : inlineContext ) : string
{
  val id = if (ref != "") then ref.definitionId else txt.definitionId
  val elemName = if (isImage) then "img" else "a"
  match(contxt.links[id]) {
    Just(link) -> {
      val attrsd = contxt.defaults.matchRules(elemName,attrs)
      val xlink = if (attrsd.empty) then link else link( linkattrs = attrsd.mergeDefault(link.linkattrs) )
      nbsp + contxt.fmtLink(isImage, xlink, contxt.formatInline(txt))
    }
    Nothing -> {
      // Link not found! Try if it is a label
      val labelId = if (id.startsWith("#")) then id.substr(1) else ""
      match(contxt.labels[labelId]) {
        Just(lab) -> {
          // Label reference
          val attrsd = contxt.defaults.matchRules(elemName,attrs)
          val lattrs = attrsd.addKeyval("target-element",lab.element)
          val llink  = newLink(id,contxt.formatInline(lab.labelCaption),lattrs,bench=contxt.bench)
          nbsp + contxt.fmtLink(isImage,llink,contxt.formatInline(
                                 if (ref=="") then "&" + labelId + ";" else txt))
        }
        Nothing -> {
          if (ref != "") then {
            warning( "missing link definition: " + ref)
            spaces + contxt.formatInline(txt) + "[??]"
          }
          elif (!(attrs.empty)) then {
            // Span element
            spaces + contxt.fmtSpan(txt,attrs)
          }
          else {
            // warn for missing labels or links
            if (txt.contains(rxCanBeRef)) then {
              if (txt.startsWith("#")) then {
                warning( "reference to missing id: " + txt)
              }
              elif (contxt.labels[id].isJust) then {
                warning( "possibly forgot '#' to reference id: " + txt)
              }
              else {
                warning( "possibly missing link definition or id: " + txt)
              }
            }

            // just brackets
            spaces + "[" + formatInline(contxt,txt) + "]" + formatInline(contxt,after)
          }
        }
      }
    }
  }
}

val rxCanBeRef = regex(r"^#?[A-Za-z_][\w-]*$")

// get and format default attributes
fun formatDefaults( contxt : inlineContext, attrs : attrs, elemName : string = "" ) : attrs {
  if (!(attrs.defaults)) return attrs

  val sname = if (elemName != "") then elemName
              elif (attrs.elem != "") then attrs.elem
              else match (attrs.classes) {
                Cons(cname,_) -> cname
                _             -> "span"
              } //attrs.elementName("span")
  val attrsx  = contxt.defaults.matchRules(sname,attrs)
  contxt.formatAttrs(attrsx)
}

// Format a span element
fun fmtSpan( contxt : inlineContext, txt0 : string, attrs : attrs ) : string {
  val sname   = if (attrs.elem != "") then attrs.elem
                else match (attrs.classes) {
                  Cons(cname,_) -> cname
                  _             -> "span"
                } //attrs.elementName("span")
  val attrsx  = contxt.defaults.matchRules(sname,attrs)
  val attrsd  = contxt.formatAttrs(attrsx)

  val txt = attrsd.transformText(txt0,contxt.labels,contxt.metadata)
  match(attrsd.input) {
    Pre      -> contxt.fmtCode("", txt, attrsd) // todo: use sname as env name?
    Math     -> contxt.fmtMath(False,txt.mathUnline,attrsd)
    MathPre  -> contxt.fmtMath(False,txt.mathUnline.mathPre,attrsd)
    Raw(monly) -> {
      if (contxt.sanitize) then ""
       else match(monly) {
        Nothing -> contxt.fmtCmd("span", txt, attrsd )
        Just(f) | f == contxt.fmt -> contxt.fmtCmd("span", txt, attrsd )
        _       -> ""
       }
    }
    Markdown(Just(f)) | !(f == contxt.fmt) -> ""
    Markdown | attrsd.notag -> contxt.formatInline(txt)
    // MathDefs, Tex, Markdown
    _  -> contxt.fmtCmd("span", contxt.formatInline(txt), attrsd )
  }
}

fun mathUnline( txt : string ) {
  txt.replaceAll(rxCont,"$1")  // allow line breaks in inline-math
}
val rxCont = regex(r"(\\%)|(?:%.*)?\n[ \t]*")

// Format a citation link
fun fmtCite(contxt : inlineContext, nbsp: string, citations : list<cite>, attrs : attrs ) : string
{
  val cs0 = match(attrs.hasKey("cite-style")) {
              Just(cstext) -> parseCiteStyleDef(cstext)
              Nothing      -> contxt.citestyle
            }
  val cs1 = match(cs0.mode) {
              Auto -> match(citations) {
                        Cons(cite,_) | cite.authors != "" -> citeNatural
                        _  -> citeNumeric
                      }
              _ -> cs0
            }
  val cs = if (attrs.hasClass("free")) then cs1(open="",close="") else cs1

  val isTextual = (attrs.hasClass("textual") || cs.mode.isTextual)

  fun makeParens(text) {
    cs.open + text + cs.close
  }

  fun makeLink(cite:cite,text:string) :string {
    "[" + text + "][#" + cite.name + "]{.bibref}"
  }

  // Takes a list of citations that share common authors
  fun fmtAuthorYear(cites : list<cite> ) {
    val (modifier,authors,pre,post) = match(cites) {
      Cons(cite,_) -> (cite.modifier,cite.authors,cite.pre,cite.post)
      _ -> ("","?","","")  // should never happen
    }
    val links = cites.map(fn(cite){ makeLink(cite,cite.year) }).join(cs.yysep)
    val plinks= if (isTextual && !(modifier.contains("-"))) then makeParens(links) else links
    val sep   = if (isTextual) then "&nbsp;" else cs.aysep


    if (authors=="") then {
      warning( "author-year citation but this bib style does not support this: " +
              cites.map(fn(cite){ "r" + cite.name }).join(", "))
    }
    val authorslink = match(cites) {
      Cons(cite,_) | !isTextual -> makeLink(cite,authors)  // authors link to first citation
      _            -> authors
    }
    val mid  = if (modifier=="!")
                 then authorslink
               elif (modifier=="-" || authors=="")
                 then plinks
                 else authorslink + sep + plinks
    pre + mid + post
  }

  fun fmtNumeric(cite : cite) {
    val mid  = if (cite.modifier=="!") then cite.authors else makeLink(cite,cite.number)
    cite.pre + mid + cite.post
  }

  fun fmtNumericSpan( cite1 : cite, cite2 : cite ) : string {
    val link1 = makeLink(cite1,cite1.number)
    val link2 = makeLink(cite2,cite2.number)
    cite1.pre + link1 + r"\/--\/" + link2 + cite1.post
  }

  // compress numeric citations
  fun takeSeq1(cite:cite, fin:cite, cites : list<cite> ) : maybe<cite> {
    match(cites) {
      Cons(citex,citesx) | citex.ordinal == fin.ordinal+1
        -> takeSeq1(cite,citex,citesx)
      _ -> if (fin.ordinal - cite.ordinal <= 1) then Nothing else Just(fin)
    }
  }

  fun takeSeq(cite:cite, cites : list<cite> ) : maybe<cite> {
    if (cite.modifier=="!") then return Nothing
    if (cite.ordinal<=0) then return Nothing
    match(cites) {
      Cons(citex,citesx) -> {
        if (citex.ordinal == cite.ordinal+1)
         then takeSeq1(cite,citex,citesx)
         else Nothing
      }
      Nil -> Nothing
    }
  }

  fun fmtCompressed( cites : list<cite>, done : int = ~1 ) : list<string>
  {
    match(cites) {
      Cons(cite,rest0) ->
        if (done >= cite.ordinal) then fmtCompressed(rest0,done) else {
          match(takeSeq(cite,rest0)) {
            Just(fin) -> Cons(fmtNumericSpan(cite,fin), rest0.fmtCompressed(fin.ordinal))
            Nothing     -> Cons(fmtNumeric(cite), rest0.fmtCompressed())
          }
        }
      Nil -> Nil
    }
  }

  // Group common authors together for author-year citations.
  // We pass an explicit "done" list so Koka can see this is terminating
  fun groupAuthors( cites : list<cite>, done : list<string> ) : list<list<cite>> {
    match(cites) {
      Nil -> Nil
      Cons(cite,rest) -> {
        if (done.any( fn(s) { s == cite.modifier + cite.authors }))
          then groupAuthors(rest,done)
          else {
            val same = rest.filter( fn(citex) {
                          (citex.authors == cite.authors) && (citex.modifier == cite.modifier) } )
            if (same.isNil)
             then Cons([cite], rest.groupAuthors(done))
             else Cons( Cons(cite,same), rest.groupAuthors( Cons(cite.modifier + cite.authors, done)) )
          }
      }
    }
  }

  fun fmtAuthorYears( cites : list<cite> ) : list<string> {
    cites.groupAuthors([]).map(fmtAuthorYear)
  }


  fun fmtNumerics( cites : list<cite> ) : list<string> {
    // group numeric citations?
    if (cs.compress) then cites.fmtCompressed else cites.map(fmtNumeric)
  }

  fun fmtTextualNumerics( cites : list<cite> ) : list<string> {
    cites.map(fn(cite){ fmtAuthorYear([cite(year = cite.number)])} )
  }

  fun fmtCitations(cites : list<cite> ) : list<string> {
    fun gtCite(cite1,cite2) { cite1.ordinal > cite2.ordinal }
    val scites = if (cs.sort) then cites.isort(gtCite) else cites
    match(cs.mode) {
      Natural -> fmtAuthorYears(scites)
      Textual -> fmtAuthorYears(scites)
      _ | isTextual -> fmtTextualNumerics(scites)
      _ -> fmtNumerics(scites)
    }
  }

  val citeText = citations.fmtCitations.join(cs.citesep + r"\/")  // add \/ or nbsp's are inserted.
  val pciteText = if (isTextual) then citeText else makeParens(citeText)

  val sciteText = match(cs.mode) {
    Super -> r"\/^" + pciteText + r"^\/"
    _     -> pciteText
  }

  (if (cs.mode.isSuper) then "" else nbsp) + contxt.fmtCmd("span", contxt.formatInline(sciteText), attrs.addClass("citations"))
}


val rxEtAl       = regex(r"\bet(?: |&nbsp;|\\ )al.(?!_)")


// Format attributes
fun formatAttrs( contxt : inlineContext, attrs : attrs ) : attrs {
  attrs( label = contxt.formatInline(attrs.label) ).expand(contxt.metadata )
}

// Apply defaults
fun applyDefaults( contxt : inlineContext, sname : string, attrs : attrs ) : attrs {
  contxt.defaults.matchRules(sname,attrs)
}

fun inlineFootnote( cap : matched, contxt : inlineContext ) : string {
  val id = cap.groups[1].definitionId
  match( contxt.footnotes[id] ) {
    Just(foot:footnote) -> contxt.fmtFootnote(id,foot(footnoteNum = contxt.formatInline(foot.footnoteNum),
                                                   footnoteCaption = contxt.formatInline(foot.footnoteCaption)))
    Nothing -> {
      warning( "missing footnote definition: " + cap.groups[1])
      contxt.fmtText("[^" + formatInline(contxt,cap.groups[1]) + "]") // leave as plain text?
    }
  }
}

fun isort( xs : list<a>, gt : (a,a) -> bool ) : list<a> {
  match(xs) {
    Cons(x,xx) -> insert(x,xx.isort(gt),gt)
    Nil -> Nil
  }
}

fun insert( x : a, xs : list<a>, gt : (a,a) -> bool ) : list<a> {
  match(xs) {
    Cons(y,yy) -> if (gt(x,y)) then Cons(y,insert(x,yy,gt)) else Cons(x,xs)
    Nil -> [x]
  }
}
