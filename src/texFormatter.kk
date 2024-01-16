/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Formatting of TeX elements (i.e. emphasis, links, etc.)
module texFormatter

import std/os/path
import std/data/dict
import std/text/regex
import common
import entity
import inline
import options
import texCommon      // for texAccents et al
import attributes
import codeAlign

pub fun fmtTexEnv(contxt : inlineContext, env : string, txt : string, attrs : attrs ) : string {
  if (env=="") 
   then texText(txt) 
   else texEnv(env,txt,attrs)
}

pub fun fmtTexCmd(contxt : inlineContext, cmd : string, txt : string, attrs : attrs ) : string {
  if (cmd=="") then texText(txt) 
  elif (cmd=="br") then "\\mdBr\n" 
  // elif (cmd=="code") then "\\lstinline|" + txt + "|" 
  else texCmd(cmd,txt,attrs)
}

pub fun fmtTexLineInfo( contxt : inlineContext, lineInfo : string ) : string {
  "%mdk-data-line={" + lineInfo + "}\n{}"
}

pub fun fmtTexEscape( contxt : inlineContext, txt : string, allowEntity : bool ) : string {
  //texText(htmlEscape(txt,allowEntity))
  if (allowEntity)
   then texText(htmlEscape(txt,allowEntity))
   else // we use lstlisting with 'mathescape' and escape just $ and |
        txt.replaceAll(regex(r"\$"),r"$\mbox{\$}$").replaceAll(regex(r"\|"),r"$\mbox{\char124}$")  
}

pub fun fmtTexFootnote(contxt : inlineContext, id : string, foot : footnote ) : string {
  "\\mdFootnote[id=back-fn-" + id + ",label={" + foot.footnoteNum + "}]{" + ((foot.footnoteContent)(contxt)) + "}"
}

pub fun fmtTexLink( contxt : inlineContext, isImage : bool, link : link, content : string ) {
  val attrs = if (link.linkid.bool) then link.linkattrs.addKeyval("data-linkid",link.linkid) else link.linkattrs
  if (isImage) then {
    texCmd("img",link.href,attrs)
  }
  else {
    texCmd("a", texLinkText(if (link.href.startsWith("#")) then link.href.substr(1) else link.href),attrs) +
      "{" + (if (link.linkattrs.hasClass("tex-tooltip")) then extractText(link.title) else "") + "}" +
      "{" + content + "}"    
  }
}

fun extractText( s : string ) : string {
  s.replaceAll(regxTexCmd," ")
}

val regxTexCmd = regex(rxTexCmd)

pub fun fmtTexCodePlain( contxt : inlineContext, txt : string, startline : bool ) : string 
{
  txt.htmlEscape(False).texText.preSpace(startline)
}

pub fun fmtTexCodeToken(contxt : inlineContext, classes : list<string>, txt : string, lang : string, attrs : attrs ) : string
{
  val start = if (classes.any(fn(cname) { cname=="white" })) 
                then "{"  // so preindent can match
                else {
                  val cclasses = classes.map(fn(cname) { 
                                    cname.replaceAll(regex(r"(?:^|[^a-z]+)(?:([a-z])([a-z]*))?",ignoreCase=True),fn(ccap) {
                                      ccap.groups[1].toUpper() + ccap.groups[2]
                                    }).replaceAll(regex(r"[^a-zA-Z]+"),"")
                                  }).filter( fn(cname) { cname != "" && cname != "Token" })
                  r"\mdToken{" + cclasses.join(",") + "}{"
                }
  val end = "}"
  start + txt + end     
}

/*
fun fmtTexCodeHilite( context : inlineContext, txt : string, startLine : bool ) : (string) 
{
  unTokenize(txt,startLine)
}


fun unTokenize( txt : string, startLine : bool ) : string {
  var nl := startLine
  txt.replaceAll(rxTagged, fn(cap) {
        if (cap.groups.matchedOn(1)) {
          val res = cap.matched.texText.preSpace(nl)
          nl := False
          res
        }
        elif (cap.matched=="<br>") then {
          nl := True
          "\\prebr{}\n" 
        }
        else cap.matched
      })
      .replaceAll(rxToken, fn(cap) {
        val classes=cap.groups[1].toLower.trim.split(rxSpaces).list
        context.fmtTexCodeToken( classes, cap.groups[2], "", attrsNone )    
      })
} 
val rxToken = regex(r#"<span\s+.*?\bclass=['"]?([^"']+)['"]?[^>]*>([\s\S]*?)</span>"#,ignoreCase=True)
val rxBr = regex(r"\n|<br>")
val rxTagged = regex(r"([^<>]+)|<([^>]*)>")
*/

pub fun preSpace( txt : string, start : bool = True ) : string {
  txt.replaceAll(rxIndent,fn(cap){ cap.groups[1] + (if (start) then r"\preindent" else r"\prespace") + "{" + cap.groups[2].length.show + "}" })
     .replaceAll(rxSpaces,fn(cap){ r"\prespace{" + cap.matched.length.show + "}"})
     .replaceAll("\n|<br>","\\prebr{}\n")
     .replaceAll("`","{`}")
}
val rxIndent = regex(r"(^|\n)( +)")
val rxSpaces = regex(r" +")

fun texLinkText( txt : string ) : string {
  txt.replaceAll("~","\\textasciitilde ").replaceAll("%","\\%").replaceAll("#","\\#")
}

pub fun texText( txt : string ) : string {
  txt.replaceAll(rxSpecial,texSpecial).replaceAll(rxEntity,texEntity)     
}

val rxEntity  = regex(r"&((?:#[xX]?)?(\w)(\w*));")
val rxSpecial = regex(r"&#?\w+;|[" + specials.map(fst).join + r"\]")
val specials = [
  (r"%", r"\%"),
  (r"~", r"{\textasciitilde}"),
  (r"#", r"\#"),
  (r"&", r"\&"),  // defined by madoko.sty
  (r"$", r"\$"),
  (r"{", r"\{"),
  (r"}", r"\}"),
  (r"_", r"\_"),
  (r"^", r"{\textasciicircum}"),
  (r"|", r"{\textbar}"),
  (r"<", r"{\textless}"),
  (r">", r"{\textgreater}"),
  (r"\",r"{\textbackslash}"),  // must come last, see rxSpecial that appends a "\"
]

val rxNamedEntity = regex(r"&(\w+);")

fun escapeEntity( s : string ) : string {
  s.replaceAll(rxNamedEntity,"&amp;$1;")
}

fun texSpecial( cap : matched ) : string {
  match(specials.find(fn(kv){ kv.fst == cap.matched })) {
    Nothing  -> cap.matched
    Just(kv) -> kv.snd
  }
}

val accents 
  = texAccents.list.map(fn(te) { (te.snd, te.fst ) }).dict

fun texEntity( cap : matched ) {
  match(accents[cap.groups[3]]) {
    Just(cmd) -> r"{\" + cmd + "{" + cap.groups[2] + "}}"
    Nothing   -> entityToTex(cap.groups[1])
  } 
}

fun texCmd( cmd : string, body : string, attrs : attrs = attrsNone, pre : string = "md" ) : string {
  val cmdName = if (attrs.texelem != "") then attrs.texelem else (pre + cmd.normalizeCmd.capitalize)
  "\\" + cmdName + attrs.texAttrsX + "{" + body + "}"
}

pub fun fmtTexCodeTable( contxt : inlineContext, ct : codeTable, attrs : attrs ) : string {
  val table = if (attrs.hasClass("long")) then "LongTable" else "Table"
  "\\begin{mdCode" + table + "}" + attrs.texAttrsX + "{" + ct.columns.show + "}" + "{" + list(1,ct.columns).map(fn(_) {"l"}).join("") + "}\n" +
    ct.rows.map( fn(row) { row.map(fmtTexCodeCell).join("&") }).join("\\\\\n") +
  "\n\\end{mdCodeTable}\n"
}

fun fmtTexCodeCell( ccell : ccell ) : string {
  val align = if (ccell.center) then "c" else "l"
  if (ccell.span <= 1) then ccell.content else "\\multicolumn{" + ccell.span.show + "}{" + align + "}{" + ccell.content + "}"
}

pub fun fmtTexTable( contxt : inlineContext, head : list<row>, body : list<row>, colattrs : list<attrs>, attrs : attrs ) : string {
  val pre = "md"
  val rows = head + body
  val td = if (attrs.hasClass("columns")) then "column" else "td"
  val table = if (attrs.hasClass("long")) then "LongTable" else "Table"
  val columns = max(1,rows.map(fn(r:row){ r.cells.length }).maximum)
  val colattrsx = (colattrs + list(colattrs.length,columns).map(fn(i){ attrsNone })).take(columns)
  "\\begin{" + pre + table + "}" + attrs.addClass("block").texAttrsX + 
      "{" + columns.show + "}" + 
      "{" + colattrsx.map(fmtColumn).join + "}\n" +
    head.fmtRows("th",pre) + "\n" +
    body.fmtRows(td,pre) +
    "\\end{" + pre + table + "}\n"
}

type line {
  Single
  Double
  NoLine
}

val fmtRowLineBreak = "\\morecmidrules\n" // \\\\[-\\mdTablelineskip]\n"

fun fmtColorArg( clr : string ) : string {
  val c = clr.normalizeColor  
  if (c.startsWith("#")) 
    then "[HTML]{" + c.substr(1) + "}"
  elif (c.startsWith("\\#")) 
    then "[HTML]{" + c.substr(2) + "}"
    else "{" + c.substr(0,1).toUpper + c.substr(1).toLower + "}"
}

fun fmtColumn( colattr : attrs ) : string {
  "l"
}

fun fmtRows( rows : list<row>, td : string, pre : string ) : string {
  var lastIsLine := False
  val xrows = rows.map fn(row) {
    val lineRow = row.cells.map(fn(cell) { 
                    if (cell.cellAttrs.hasClass("cell-line")) then Single
                    elif (cell.cellAttrs.hasClass("cell-double-line")) then Double 
                    else NoLine 
                  } )
    if (!(lineRow.all(isNoLine))) then { 
      val res = (if (lastIsLine) then fmtRowLineBreak else "") + fmtLine(lineRow,row)
      lastIsLine := True
      res
    }
    else {
      val res = (if (lastIsLine) then "\n" else "") + fmtRow(td,row,pre)
      lastIsLine := False
      res
    }
  }
  xrows.join() + (if (lastIsLine) then "\n" else "")
}


fun fmtLine( lines : list<line>, row : row ) : string 
{
  fun width( cattrs : attrs ) {
    match(cattrs.hasKey("rule-width")) {
      Just(wd) -> "[" + wd.normalizeVal + "]"
      Nothing  -> ""
    }
  }

  val line2 = if (!(lines.any(isDouble))) then "" else {
    fmtRowLineBreak + 
     zipWithIndexed(row.cells,lines,fn(i,cell,line) {
      val attrs = cell.cellAttrs
      if (!(line.isDouble)) then "" 
       else "\\cmidrule" + width(attrs) + "{" + (i+1).show + "-" + (i+ attrs.lookupKey("column-span","1").parseInt.maybe(1,id)).show + "}" 
     }).join            
  }
  
  val line1 = if (!(lines.any(isNoLine)) && line2=="") then "\\midrule" + width(row.rowAttrs) else {
    zipWithIndexed(row.cells,lines,fn(i,cell,line) {
      val attrs = cell.cellAttrs
      if (line.isNoLine) then "" 
       else "\\cmidrule" + width(attrs) + "{" + (i+1).show + "-" + (i+ attrs.lookupKey("column-span","1").parseInt.maybe(1,id)).show + "}" 
     }).join
  }
  
  line1 + line2
}

fun fmtRow( td : string, row : row, pre : string ) : string {
  /*
  rcolor = match (row.rowAttrs.hasKey("background-color")) {
             Nothing   -> ""
             Just(clr) -> "\\rowcolor" + fmtColorArg(clr)
           }     
  rcolor + */
  row.cells.map(fn(cell) { fmtCell(td,cell.text.trim,cell.cellAttrs,pre) }).join("&") 
    + "\\\\\n"
} 



fun fmtCell( elem : string, body : string, attrs : attrs, pre : string ) : string {
  val colspan = attrs.lookupKey("column-span","1")
  val align   = match(attrs.hasKey("text-align")) {
                  Just(alignment) -> alignment.substr(0,1)
                  Nothing -> if (elem=="th") then "c" else "l" 
                }
  val bcolor  = match (attrs.hasKey("background-color")) {
                  Nothing   -> ""
                  Just(clr) -> "{\\cellcolor" + fmtColorArg(clr) + "}"
                }            
  val fmt     = (if (attrs.hasClass("cell-border-left")) then "|" else "") + align +
                (if (attrs.hasClass("cell-border-right")) then "|" else "")

  val attrsx  = attrs( classes = attrs.classes.filter(fn(c){ c != "cell-border-left" && c != "cell-border-right" && !(c.startsWith("align-"))}),
                       keyvals = attrs.keyvals.filter(fn(kv){ kv.fst != "column-span" && kv.fst != "background-color" }))

  val content = if (elem=="column") 
                 then texEnv(elem,body,attrsx)
                 else texCmd(elem,body,attrsx.addKeyval("display","table-cell")) 
                 
  if (colspan=="1" && fmt=="l" && bcolor=="") then content 
   else "\\multicolumn{" + colspan + "}{" + fmt + "}{" + bcolor + content + "}"
}




fun texAttrsX( attrs : attrs = attrsNone ) : string {
  if (attrs.empty) then "" else {
    val txt = [ if (attrs.classes.isNil) then [] else ["class={" + attrs.classes.map(normalizeId).join(",") + "}"],  // so block goes first
                if (attrs.name=="") then [] else ["id=" + attrs.name],
                if (attrs.label=="") then [] else ["label={" + attrs.label.escapeEntity.texText + "}"],
                if (attrs.elem=="") then [] else ["elem={" + attrs.elem.escapeEntity.texText + "}"],
                attrs.keyvals.filter(nosuppressKey).map(fn(kv) { 
                  val (name0,value) = kv
                  val name = if (name0.startsWith("tex-")) then name0.substr(4) else name0    
                  showAttr( name, value )
                }),          
              ].concat.join(",") 
    if (txt=="") then "" else "[" + txt + "]"
  }
}


fun nosuppressKey( kv : (string,string) ) : bool {
  val key = kv.fst
  (key != "source" && !(key.startsWith("html-") || key.startsWith("css-")))
}


fun showAttr( key, value ) {
  val csskey = key.normalizeId
  val cssval = if (csskey=="color" || csskey.endsWith("-color")) then value.normalizeColor 
               elif (csskey=="max-width" || csskey=="max-height") then value.normalizeVal("\\naturalwidth")
               else value.normalizeVal
  csskey + "={" + cssval + "}" 
}

fun normalizeColor( v : string ) : string {
  match(v.find(rxRgbX)) {
    Just(cap) -> {
      if (cap.groups[4]=="")
       then "\\#" + [1,1,2,2,3,3].map( fn(i) { cap.groups[i] } ).join.toUpper
       else "\\" + v.trim.toUpper
    }
    Nothing -> normalizeVal(v)
  }
}

fun normalizeVal( v0 : string, percwidth="\\linewidth" ) : string {
  val v = v0.splitExclude(rxComma,rxQuoted).join(",")
  match(v.find(rxPerc)) {
    Just(cap) -> {
      val perc = cap.groups[1].parseInt().maybe(100,id).double / 100.0
      perc.showFixed(2) + percwidth
    }
    Nothing -> match(v.find(rxPixels)) {
      Just(cap) -> cap.groups[1] + "\\cssPixel"
      Nothing   -> match(v.find(rxRgb)) {
        Just(cap) -> {
          val rgb = [cap.groups[1],cap.groups[3],cap.groups[4]].map( fn(c) { c.parseIntDefault(0) } )
          val hrgb = if (cap.groups[2]=="%") then rgb.map( fn(p) { (p.double * 2.55).int } ) else rgb
          "\\#" + hrgb.map(fn(c) { c.showHex(2) } ).join
        }
        Nothing   -> match(v.find(rxHsl)) {
          Just(cap) -> {
            val (r,g,b) = hslToRgb( cap.groups[1].parseIntDefault(0), cap.groups[2].parseIntDefault(0), cap.groups[3].parseIntDefault(0) )
            "\\#" + [r,g,b].map( fn(c) { c.showHex(2) } ).join
          }
          Nothing -> v.escapeEntity.texText.replaceAll(regex("\n"),"\\\\")
        }
      }
    }
  }
}

val rxPerc = regex(r"^\s*(\d{1,3})%\s*$")
val rxPixels = regex(r"^\s*(\d+(?:\.\d+)?)px\s*$")

val rxRgbX = regex(r"^\s*#([a-fA-F0-9])([a-fA-F0-9])([a-fA-F0-9])([a-fA-F0-9]{3})?")
val rxRgb = regex(r"^\s*rgba?\((\d+)(%)?,(\d+)%?,(\d+)%?(?:,\d+%?)?\)\s*$")
val rxHsl = regex(r"^\s*hsla?\((\d+),(\d+)%?,(\d+)%?(?:,\d+%?)?\)\s*$")

val rxComma  = regex(r"\s*,\s*")
val rxQuoted = regex(r#"'[^']*'|"[^"]*""#)

fun hslToRgb(hi, si, li){
  val h = (hi%360).double / 360.0;
  val s = si.double * 0.01;
  val l = li.double * 0.01;

  if (s==0.0) then {
    val x = (l*255.0).int
    return (x,x,x)
  }

  val q = if (l < 0.5) then l * (1.0 + s) else l + (s - (l * s));
  val p = (2.0 * l) - q;
  
  fun hue2rgb(t0) {
    val t = if (t0 < 0.0) then t0+1.0 elif (t0 > 1.0) then t0 - 1.0 else t0;
    val c = if (t < 1.0/6.0) then p + (q - p) * 6.0 * t
            elif (t < 0.5) then q
            elif (t < 2.0/3.0) then p + (q - p) * (2.0/3.0 - t) * 6.0
            else p
    (c * 255.0).int            
  }

  (hue2rgb(h + 1.0/3.0), hue2rgb(h), hue2rgb(h - 1.0/3.0))
}


fun texEnv( env : string, body : string, attrs : attrs = attrsNone ) : string {
  texEnvPlain(env,body,attrs)
}

fun texEnvPlain( env : string, body : string, attrs : attrs ) : string {
  val envName = (if (attrs.texelem != "") then attrs.texelem else ("md" + env.normalizeCmd.capitalize))
  val envCmd = "\\begin{" + envName + "}" + attrs.texAttrsX + "%mdk\n" +
                body.trimRight + "%mdk\n" +
               "\\end{" + envName + "}%mdk\n"
  match(attrs.hasKey("float")) {
    Nothing   -> envCmd
    Just(flt) -> "\\mdFloatBox{" + flt + "}{" + attrs.lookupKey("lines","") + "}{" + envCmd + "}"
  }               
}

fun texClassName( attrs : attrs, def : string ) : (string,attrs) {
  val name = attrs.elementName(def)
  (name.normalizeCmd.capitalize,attrs(classes=attrs.classes.filter(fn(c){ c != name })))    
}

/* --------------------------------------
  Entities 
---------------------------------------- */

fun normalizeCmd( cmd : string ) {
  cmd.replaceAll(rxCmdSpecial,"").replaceAll(rxDigits) fn(cap) {
    list(1,cap.matched.parseInt.maybe(0,id)).map(fn(i) { "x" }).join
  }
}
val rxDigits = regex(r"\d+")
val rxCmdSpecial = regex(r"[^a-zA-Z0-9]")
