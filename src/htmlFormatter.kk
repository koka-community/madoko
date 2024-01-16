/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Formatting of  HTML elements 
module htmlFormatter

import std/data/dict
import std/text/regex
import std/os/path
import common
import inline
import options
import codeAlign
import attributes // expandKeys

pub fun fmtHtmlEnv(contxt : inlineContext, env : string, txt : string, attrs : attrs ) : string {
  if (env=="") 
   then txt 
   else tagEnv(env.translate(attrs,contxt.sanitize), (if(env.length>3) then "\n" else "") ++ txt,attrs,contxt.sanitize)
}


pub fun fmtHtmlCmd(contxt : inlineContext, cmd : string, txt : string, attrs : attrs ) : string {
  if (cmd=="") then txt else tag(cmd.translate(attrs,contxt.sanitize),txt,attrs.htmlFormat(cmd,contxt.sanitize))
}

pub fun fmtHtmlLineInfo(contxt : inlineContext, lineInfo : string ) : string {
  "<span data-line=\"" ++ lineInfo ++ "\"></span>"
}


fun translate(tagName : string, attrs : attrs, sanitize : bool ) : string  {
  if (attrs.empty || sanitize) return tagName
  if (attrs.htmlelem != "") 
   then attrs.htmlelem
   else tagName
}

pub fun fmtHtmlEscape(contxt : inlineContext, txt : string, allowEntity : bool ) : string {
  htmlEscape(txt,allowEntity)
}

pub fun fmtHtmlFootnote(contxt : inlineContext, id : string, foot : footnote ) : string {
  tag("sup", 
    tag("a", foot.footnoteNum, " href=\"#fn-" ++ escape(id) ++ "\" " +
          "title=\"" ++ foot.footnoteCaption.extractText.escape ++ "\" " +
          "class=\"footnote-ref localref\" " ),
          " id=\"back-fn-" ++ escape(id) ++ "\" " )
}

pub fun fmtHtmlTable( contxt : inlineContext, head : list<row>, body : list<row>, colattrs : list<attrs>, attrs : attrs  ) : string {
  tag("table", 
    contxt.fmtRows("thead","th",head) ++ contxt.fmtRows("tbody","td",body),
    attrs.addClass("block").htmlFormat("table",contxt.sanitize))
}

fun fmtRows( contxt : inlineContext, tbody : string, td : string, rows : list<row> ) : string {
  if (rows.isNil) then return ""
  tagBlock(tbody,
    rows.map( fn(row) {
      tag("tr", row.cells.map(fn(cell) { 
                    val cattrs1 = match(cell.cellAttrs.hasKey("rule-width")) {
                                     Just(wd) -> cell.cellAttrs
                                                  .addKeyvalIfNotExist("border-top-width",wd)
                                                  .addKeyvalIfNotExist("border-bottom-width",wd)
                                     Nothing  -> cell.cellAttrs
                                   }
                    tag(td,cell.text, cattrs1.htmlFormat(td,contxt.sanitize)) 
                }).join, 
                //row.rowAttrs.htmlFormat("tr",contxt.sanitize)
                "") 
    }).join("\n"))
} 

pub fun fmtHtmlCodeTable( contxt : inlineContext, ct : codeTable, attrs : attrs ) : string {
  tag("table", tagBlock("tbody", contxt.fmtCtRows( ct.rows ) ), attrs.addClass("block").htmlFormat("table",contxt.sanitize) )
}

fun fmtCtRows( contxt : inlineContext, rows : list<crow> ) : string {
  rows.map( fn(row) {
    tag("tr", row.mapIndexed( fn(i,cell) {
                val empty = cell.content.isAllWhite
                val expander = if (row.length==i+1) then " expander" else ""
                val classes = "colspan" ++ cell.span.show ++ expander ++ (if (empty) then " empty" else "")
                val attrs = " class='" ++ classes ++ "'" ++ (if (cell.span > 1) then " colspan='" ++ cell.span.show ++ "'" else "")
                tag("td", if (empty) then "&nbsp;" else cell.content, attrs )                
              }).join, "")
  }).join("\n")  
}

fun isAllWhite( s : string ) : bool {
  s.contains(rxWhite)
}
val rxWhite = regex(r"^\s*$")

/*
fun isHtmlWhite( s : string ) : bool {
  s.find(rxAllWhite).bool
}
val rxAllWhite = regex(r"^(\s|&nbsp;|<span\b[^>]*>(\s|&nbsp;)*</span>)*$")
*/

val htmlImageExtensions = [".png",".jpg",".jpeg",".svg",".gif",".tif",".tiff",".bmp",".jpx",".jp2"]

pub fun fmtHtmlLink( contxt : inlineContext, isImage : bool, link : link, content : string ) {
  if (isImage) then {
    // expand extensions and set file refers
    val hrefs0  = link.href.expandChoices
    // legacy support for auto converting eps or pdf to png.
    val hrefs = match(hrefs0) {
      Cons(href,Nil) | href.extname.toLower == ".eps" || href.extname.toLower == ".pdf"
        -> [href,href.changeExt(".png")]
      _ -> hrefs0
    }
    hrefs.foreach fn(href) {
      if (href.relative) then log("filesRefer", href);
    }
    // pick best one for images
    val imgref = pickExtension(htmlImageExtensions, hrefs)

    val href = match (contxt.embedinfos[imgref]) {
      Just(info) | info.embedData != "" -> {
        //trace("embedded: " ++ info.embedName)
        info.embedData 
      }
      _          -> {
        if (imgref.relative) then {
          // if (isPS) then log("filesRefer",pick) // refer to eps/pdf too
          // log("filesRefer",imgref);
          log("embed", imgref);
        }
        imgref.escape
      }
    }    
    "<img src=\"" ++ href ++ "\"" +
      (if (link.title != "") then " title=\"" ++ link.title.extractText.escape ++ "\"" else "") +
      (if (content != "") then " alt=\"" ++ content.escape ++ "\"" else "") +
      (if (imgref.startsWith("data:image")) then "" else " data-path=\"" ++ imgref.escape ++ "\"") +
      (if (link.linkid != "") then " data-linkid=\"" ++ link.linkid.escape ++ "\"" else "") +
      link.linkattrs.htmlFormat("img",contxt.sanitize) ++ ">"
  }
  else {
    "<a href=\"" ++ link.href.escape ++ "\"" +
      (if (link.title != "") then " title=\"" ++ link.title.extractText.escape ++ "\"" else "") +
      (if (link.linkid != "") then " data-linkid=\"" ++ link.linkid.escape ++ "\"" else "") +
      link.linkattrs.htmlFormat("a",contxt.sanitize) ++ ">" ++ 
      content ++ "</a>"
  }
}

pub fun fmtHtmlSvg(contxt: inlineContext, svg : string, attrs : attrs, alt : string ) : string {
  svg.replace( rxSvg, fn(cap) {
    "<svg " ++ attrs.htmlFormat("svg",contxt.sanitize) ++ cap.groups[2] ++ cap.groups[3] +
    (if (alt.bool) then "<desc>" ++ alt.escape ++ "</desc>" else "")
  })
  /*
  if (alt=="") then svgx else {
    "<span class=\"math-svg\">" ++ svgx +
    "<span class=\"hidden math-svg-alt\">" ++ alt.escape ++ 
    "</span></span>"
  }
  */
}
val rxSvg = regex(r#"^(\s*<svg\b)((?:[^'">]|"[^"]*""|'[^']*')*)(>)"#)

fun extractText( s : string ) : string {
  s.replaceAll(rxTag,"")
}

val rxTag = regex(r"<[^\n>]*>")

pub fun fmtHtmlCodePlain( contxt : inlineContext, txt : string, startline : bool ) : string 
{
  txt.escapePre  
}

fun fmtHtmlCodeHilite( contxt : inlineContext, txt : string, startLine : bool ) : (string) 
{
  txt.replaceAll(rxEndSpaces," ")
     .replaceAll(rxToken, fn(cap) {
        val classes=cap.groups[1].toLower.trim.split(rxSpaces).list
        contxt.fmtHtmlCodeToken( classes, cap.groups[2], "", attrsNone )    
     })
} 
val rxToken = regex(r#"<span\s+.*?\bclass=['"]?(?:token *)?([^"']+)['"]?[^>]*>([\s\S]*?)</span>"#,ignoreCase=True)
val rxSpaces = regex(r"[ \t]+")
val rxEndSpaces = regex(r"  +$",multiline=True)

pub fun fmtHtmlCodeToken( contxt: inlineContext, classes0 : list<string> , txt : string, lang : string, attrs : attrs ) : string {
  /*
  val classes = classes0.filter(fn(cname) { cname!=lang && !(["source","token","ptoken","white"].contains(cname) }) })
  if (classes.isNil) then txt 
   else // "<span class=" ++ classes.join(" ").htmlQuote ++ ">" ++ txt ++ "</span>"
  */
  val xclasses = attrs.classes.filter( fn(cname) { !classes0.contains(cname) })
  contxt.fmtHtmlCmd("span",txt,attrs(classes=xclasses))
}

/* --------------------------------------
 Format attributes 
---------------------------------------- */

// Format attributes. If none, return the empty string, otherwise start with a space
pub fun htmlFormat( attrs : attrs, tag : string, sanitize : bool = True ) : string {
  if (attrs.empty || sanitize) then return ""
  val classes = attrs.classes ++ (match (attrs.hasKey("list-style-type")) {
    Just(value) | value == "dash" -> ["list-style-type-dash"]
    _ -> []
  })
  (if (attrs.name=="") then "" else " id=\"" ++ escape(attrs.name) ++ "\"") +
   (if (classes.isNil) then "" 
     else " class=\"" ++ escape(classes.join(" ")) ++ "\"") 
   ++ attrs.formatKeyvals(tag)
   // (" input=" ++ attrs.input.maybe("?",showInput)) +
   //(attrs.htmlAttributes)
}

fun formatKeyvals( attrs : attrs, tag : string ) {
  val kvs = attrs.keyvals.map(fn(kv) {
    formatKeyval(kv.fst,kv.snd,tag)
  }).filter( bool )
  val (hstyles,hattrs) = kvs.partition( fn(kv){ kv.contains(rxColon) } )
  (if (hattrs.isNil) then "" else " " ++ hattrs.join(" ")) ++ 
   (if (hstyles.isNil) then "" else " style=" ++ hstyles.join(";").htmlQuote )
}
val rxColon = regex(r"^[\w\-]+\s*:")

fun formatKeyval( key : string, value : string, tag : string ) {
  if (key.startsWith("html-")) then {
    key.substr(5) ++ "=" ++ value.htmlQuote
  }
  elif (key.startsWith("tex-")) then {
    ""
  }
  elif (key.startsWith("data-")) then {
    key ++ "=" ++ value.htmlQuote
  }
  elif (key.startsWith("cite-") || key.startsWith("math-")) then {
    "data-" ++ key ++ "=" ++ value.htmlQuote
  }
  elif (key.startsWith("css-")) then {
    key.substr(4).escape ++ ":" ++ value.cssQuote
  }
  elif ((key=="colspan" || key=="column-span") && (tag=="td" || tag=="th")) then {
    "colspan=" ++ value.htmlQuote
  }
  elif ( // ((key=="width") && (tag=="td" || tag=="th")) ||
        (key=="target" && tag=="a") ||
        (key=="start" && tag=="ol")) then
  {
    key ++ "=" ++ value.htmlQuote
  }
  //elif ((key=="align" || key=="text-align") && (tag=="td" || tag=="th")) then {
  //  "align=" ++ value.htmlQuote
  //}
  elif ((key=="width" || key=="height" || key=="text-align") && (tag=="span")) then {
    "display: inline-block; " ++ key ++ ":" ++ cssQuote(value) 
  }
  elif (value=="" || (key=="toc" || key=="toc-line" || key=="toc-depth" || key=="bookmark" ||
          key=="language" || key=="bibdata" || key=="caption" || key=="cite-label")) then {
    "" // nothing
  }
  elif (key == "font-family") then {
    key.escape ++ ":" ++ value.replaceAll("html-","").cssQuote  
  }
  else {
    key.escape ++ ":" ++ value.cssQuote
  }
}

fun htmlQuote(s) {
  "\"" ++ s.escape ++ "\""
}

fun cssQuote(s :string) {
  s.list.map(cssEscape).join
}

fun cssEscape(c) {
  if (c >= ' ' && c <= '~' && c != '\\') // && c != '"' && c != '\'' && c != '<' && c != '>') 
   then c.string
   else  "\\" ++ c.int.showHex() ++ " "
}

// fun htmlAttributes( attrs : attrs ) :  string {
//   attrs.keyvals.map(fn(kv) {
//     " " ++ kv.fst ++ "=\"" ++ kv.snd.escape ++ "\""
//   }).join()
// }

/* --------------------------------------
 Tags 
---------------------------------------- */

// output a html tag with a given body and attributes
pub fun tag( tagName : string, body : string, attrs : string = "" ) : string 
{
  if (attrs=="" && tagName=="span") then body else {
    "<" ++ tagName ++ 
     attrs ++ // (if (attrs.startsWith(" ")) then attrs else (" " ++ attrs)) ++  
     ">" ++ body ++ "</" ++ tagName ++ ">"
  }
}


// output a html block tag
pub fun tagEnv( tagName : string, body : string, attrs : attrs = attrsNone, sanitize : bool = True ) : string 
{
  tagBlock( tagName, body, attrs.htmlFormat(tagName,sanitize))
}

// output a html block tag
fun tagBlock( tagName : string, body : string, attrs : string = "" ) : string 
{
  "\n<" ++ tagName ++ 
   attrs ++ // (if (attrs.startsWith(" ")) then attrs else (" " ++ attrs)) ++  
   ">" ++ body ++ "</" ++ tagName ++ ">"
}


/* --------------------------------------
  Title 
---------------------------------------- */
fun fmtField( contxt: inlineContext, elem :string, class : string, txt : string ) : string {
  if (txt=="") return ""
  tag(elem, contxt.formatInline(txt), " class='" ++ class ++ "'")
}

/* --------------------------------------
  Full header 
---------------------------------------- */
fun embedScripts( options: options, scripts : string, metadata : dict<string> ) : string {
  (if (scripts == "") then "" else {
    val xlinks = scripts.expandKeys(metadata).splitPaths
    xlinks.map(fn(xlink) { 
      val (link,attrs) = match(xlink.find(rxScript)) {
        Nothing   -> (xlink,attrsNone)
        Just(cap) -> (cap.groups[1],parseAttrs( cap.groups[2], "script"))
      }
      match(options.embedinfos[link]) {
        Just(info) | info.embedData != "" -> 
          "<script " ++ attrs.htmlFormat("script",False) ++ ">" ++ info.embedData ++ "\n//# sourceURL=" ++ escape(link) ++ "\n</script>\n"
        _ -> {
          if (link.relative) then {
            log("filesRefer",link);
            log("embed",link);
          }
          "<script src=\"" ++ escape(link) ++ "\" " ++ attrs.htmlFormat("script",False) ++ "></script>\n" 
        }
      }
    }).join 
  })
}
val rxScript = regex(r"([^\{\s]+)\s*(?:\{((?:[^\\\}]|\\.)*)\})?")

pub fun fmtHtmlFull(html : string, options : options, metadata : dict<string> ) : string 
{
  fun expand(s) { s.expandKeys(metadata) }

  fun makeMeta(name : string, sep : string = "" ) : list<string> {
    match (metadata[name]) {
      Nothing -> []
      Just(value) -> {
        val evalue = value.expand.escape
        ["name=\"" ++ name.escape ++ "\" content=\"" ++ 
          (if (sep=="") then evalue else evalue.replaceAll(";",sep)) ++ "\""]
      }
    }
  }

  val extensions = options.math.mjext.expand.splitPaths.map(fn(path) { 
      htmlQuote( (if (path.endsWith(".js")) then path else path ++ ".js") )
    }).join(",")

  val meta = options.htmlMeta.expand.splitPaths ++
              makeMeta("copyright") ++
              makeMeta("license") ++
              makeMeta("keywords",",") ++
              makeMeta("author",",") ++
              makeMeta("description") 
                
  val htmlHead =              
    "<meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\" />\n" ++
    "<meta name=\"generator\" content=\"Madoko, version " ++ options.version ++ "\" />\n" ++
    meta.map(fn(m) { "<meta " ++ m ++ " />\n" }).join ++
    (if (options.title=="") then "" else "<title>" ++ escape(options.title.expand) ++ "</title>\n") ++
    (if (options.css == "") then "" else {
      val links = options.css.expand.splitPaths
      links.map(fn(xlink) { 
        val (link,attrs) = match(xlink.find(rxScript)) {
          Nothing   -> (xlink,attrsNone)
          Just(cap) -> (cap.groups[1],parseAttrs( cap.groups[2], "link"))
        }
        match(options.embedinfos[link]) {
          Just(info) | info.embedData != "" -> 
            "<style type=\"text/css\" " ++ attrs.htmlFormat("style",False) ++ ">\n/*# sourceURL=" ++ escape(link) ++ " */\n" ++
              info.embedData.compressCss ++ "\n  </style>\n"
          _ -> {
            if (link.relative) then {
              log("filesRefer",link);
              log("embed",link);
            }
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"" ++ escape(link) ++ "\" " ++
                    attrs.htmlFormat("link",False) ++ ">\n"             
          }
        }
      }).join 
     }) ++
     options.embedScripts(options.scripts, metadata) ++
     (if (/* options.mathmode.isStatic ||*/ options.math.mathjax=="") then "" else {
        ["<script type=\"text/x-mathjax-config\">",
         "  MathJax.Hub.Config({",
         "    tex2jax: {inlineMath: [['$','$']]},",
         r"     TeX: { ",
         r"       Macros: { mathid: ['\\mathit{#1\\hspace{0.1ex}}',1],",
         r"                 mathkw: ['\\mathsf{#1}',1],",
         r"                 mdmathindent: ['\\hspace{#1ex}',1],",
         r"                 mathpre: ['#1',1],",
         r"               },",
         if (extensions=="") then "" 
          else r"       extensions: [" ++ extensions ++ "]",
         r"     }",
         "  });",
         "  MathJax.Hub.Register.StartupHook('TeX AMSmath Ready',fun () { ",
         "    MathJax.InputJax.TeX.Definitions.environment['mdmathpre'] = ['AMSarray',null,null,null,'l','0em','0em'];", 
         "  });", 
         "</script>",
         "<script type=\"text/javascript\" class=\"preview\"",
         "  src=\"" ++ options.math.getMathjax.expand.escape ++ "\">",
         "</script>\n"
        ].join("\n")
     }) +
     options.htmlHeader.expand ++ "\n" ++
     (if (options.cssHeader == "") then "" else "<style>\n" ++ options.cssHeader.expand.indent ++ "\n</style>\n") ++
     (if (options.jsHeader == "") then "" else "<script type=\"text/javascript\">\n" ++ options.jsHeader.expand.indent ++ "\n</script>\n")

  val htmlDoc = 
    "<!DOCTYPE html>\n<html" ++ (if (options.locale.bool) then " lang=\"" ++ options.locale ++ "\"" else "") ++ ">\n" +
    "<head>\n" +
    htmlHead.indent +
    "</head>\n" +
    "<body class=\"madoko\">\n" ++ 
    html +
    options.math.svgDefs +
    "\n</body>\n" +
    options.embedScripts(options.scriptsx, metadata ) +
    (if (options.jsFooter == "") then "" else "<script type=\"text/javascript\">\n" ++ options.jsFooter.expand.indent ++ "\n</script>\n") +
    options.htmlFooter.expand ++ "\n" ++ 
    "</html>\n"

  htmlDoc
}

fun compressCss( css :string ) : string {
  css.replaceAll(rxComment,"").replaceAll(rxEmptyLines,"\n")
}

val rxComment = regex(r"/\*[\s\S]*?\*/")
val rxEmptyLines = regex(r"\r?\n([ \t]*\r?\n)+")

/* --------------------------------------
  Escape HTML Elements 
---------------------------------------- */

fun escape( s : string ) :  string
{
  s.htmlEscape(allowEntity=True)
}

fun escapePre( s : string ) :  string
{
  s.htmlEscape()  
}

