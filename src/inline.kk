/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Defines the context for _inline_ elements.
module inline

import std/data/dict
import std/text/regex
import common
import attributes  // rules
import codeAlign  // codeTable
import hilite  // hilitemode

pub fun pick(fmt : formatter, htmlElem, texElem ) {
  match(fmt) {
    FmtHtml -> htmlElem
    FmtTex  -> texElem
  }
}

pub alias cells = list<list<(string,attrs)>>

/* --------------------------------------
 The context for inline elements 
---------------------------------------- */
pub type inlineContext {
  // The parse context for inline elements. 
  // Contains a dictionary of all define "links", and the current "grammar". 
  // If "sanitize" is "True", all (user) html is supressed or escaped.
  InlineContext( grammar    : grammar<string,inlineContext>,
                 links      : dict<link>,
                 labels     : dict<label>,
                 footnotes  : dict<footnote>,
                 defaults   : rules,
                 metadata   : dict<string>,
                 mathinfos  : dict<mathinfo>,
                 embedinfos : dict<embedinfo>,
                 citestyle  : citestyle,
                 xsanitize  : bool,
                 bench      : bool,
                 verbose    : int,
                 mathStatic : bool,
                 highlight  : bool,
                 starBold   : bool,
                 sandbox    : bool,
                 prettyAlign : int,

                 xfmtCmd : (ictx:inlineContext,cmd:string,body:string,attrs:attrs) -> string,
                 xfmtEscape : (ictx:inlineContext,body:string,allowEntity:bool) -> string,
                 xfmtLink: (ictx:inlineContext,isImage : bool, link : link, content : string ) -> string,
                 xfmtFootnote: (contxt : inlineContext, id : string, foot : footnote ) -> string,
                 xfmtTable: (contxt : inlineContext, head : list<row>, body : list<row>, colattrs: list<attrs>, attrs : attrs ) -> string,
                 xfmtEnv : (contxt : inlineContext, env : string, txt : string, attrs : attrs ) -> string,
                 xfmtCodePlain : (contxt : inlineContext, txt : string, startline : bool ) -> string,
                 // xfmtCodeHilite : (contxt : inlineContext, txt : string, startLine: bool ) -> (string),
                 xfmtCodeToken : (contxt : inlineContext, classes: list<string>, txt : string, lang : string, attrs : attrs) -> string,
                 xfmtLineInfo : (contxt : inlineContext, lineInfo : string ) -> string,
                 xfmtCodeTable : (contxt : inlineContext, ct : codeTable, attrs : attrs ) -> string,
                 xfmtMathCmd : (ictx:inlineContext,cmd:string,body:string,attrs:attrs) -> string,
                 xfmtMathEnv : (contxt : inlineContext, env : string, txt : string, attrs : attrs ) -> string,
                 fmt : formatter
               )                 
}

pub struct titleinfo (
  title : string,
  subtitle : string,
  authors : list<authorinfo>,
  note : string
)

pub struct authorinfo (
  name : string,
  address : string,
  email : string,
  note : string
)

pub type footnote {
  Footnote( footnoteNum : string, 
            footnoteContent : (inlineContext) -> string,
            footnoteCaption : string  )
}

pub fun fmtCmd( contxt : inlineContext, cmd : string, txt : string, attrs : attrs = attrsNone ) : string {
  (contxt.xfmtCmd)(contxt,cmd,txt,attrs)
}

pub fun fmtEnv( contxt : inlineContext, env : string, txt : string, attrs : attrs = attrsNone ) : string {
  (contxt.xfmtEnv)(contxt,env,txt,attrs)
}

pub fun fmtMathCmd( contxt : inlineContext, cmd : string, txt : string, attrs : attrs = attrsNone ) : string {
  (contxt.xfmtMathCmd)(contxt,cmd,txt,attrs)
}

pub fun fmtMathEnv( contxt : inlineContext, env : string, txt : string, attrs : attrs = attrsNone ) : string {
  (contxt.xfmtMathEnv)(contxt,env,txt,attrs)
}

pub fun fmtCodePlain( contxt : inlineContext, txt : string, startline : bool = True ) : string {
  (contxt.xfmtCodePlain)(contxt,txt,startline)
}

//pub fun fmtCodeHilite( contxt : inlineContext, txt : string, startLine : bool = True ) : (string) {
//  (contxt.xfmtCodeHilite)(contxt,txt,startLine)
//}

pub fun fmtCodeToken( contxt: inlineContext, classes : list<string>, txt : string, lang : string, attrs : attrs ) : string {
  (contxt.xfmtCodeToken)(contxt,classes,txt,lang,attrs)
}

pub fun fmtEscapePre( contxt : inlineContext, txt : string ) : string {
  (contxt.xfmtEscape)(contxt,txt,False)
}

pub fun fmtEscape( contxt : inlineContext, txt : string ) : string {
  (contxt.xfmtEscape)(contxt,txt,True)
}

pub fun fmtText( contxt : inlineContext, txt : string ) : string {
  (contxt.xfmtCmd)(contxt,"",txt,attrsNone)
}

pub fun fmtLink( contxt : inlineContext, isImage : bool, link : link, content : string) : string {
  (contxt.xfmtLink)(contxt,isImage,link,content)
}

pub fun fmtFootnote(contxt : inlineContext, id : string, foot : footnote ) : string {
  (contxt.xfmtFootnote)(contxt,id,foot)
}

pub fun fmtLineInfo(contxt : inlineContext, lineInfo : string ) : string {
  (contxt.xfmtLineInfo)(contxt,lineInfo)
}

pub fun fmtCodeTable(contxt : inlineContext, ct : codeTable, attrs : attrs = attrsNone ) : string {
  (contxt.xfmtCodeTable)(contxt,ct,attrs)
}

// Copy an ":inlineContext"
pub fun copy( self : inlineContext,
                       grammar : grammar<string,inlineContext> = self.grammar,
                       links : dict<link> = self.links,
                       labels : dict<label> = self.labels, 
                       footnotes : dict<footnote> = self.footnotes,
                       defaults: rules = self.defaults,
                       metadata: dict<string> = self.metadata,
                       mathinfos : dict<mathinfo> = self.mathinfos,
                       embedinfos : dict<embedinfo> = self.embedinfos,
                       citestyle : citestyle = self.citestyle,
                       sanitize : bool = self.sanitize,
                       bench : bool = self.bench,
                       verbose : int = self.verbose,
                       mathStatic : bool = self.mathStatic,
                       highlight : bool = self.highlight,
                       starBold : bool = self.starBold,
                       sandbox: bool = self.sandbox,
                       prettyAlign : int = self.prettyAlign,
                       xfmtCmd = self.xfmtCmd,
                       xfmtEscape = self.xfmtEscape,
                       xfmtLink = self.xfmtLink,
                       xfmtFootnote = self.xfmtFootnote,
                       xfmtTable = self.xfmtTable,
                       xfmtEnv = self.xfmtEnv,
                       xfmtCodePlain = self.xfmtCodePlain,
                       //xfmtCodeHilite = self.xfmtCodeHilite,
                       xfmtCodeToken = self.xfmtCodeToken,
                       xfmtLineInfo = self.xfmtLineInfo,
                       xfmtCodeTable = self.xfmtCodeTable,
                       xfmtMathCmd = self.xfmtMathCmd,
                       xfmtMathEnv = self.xfmtMathEnv,
                       fmt : formatter = self.fmt  ) : inlineContext
{
  InlineContext( grammar,links,labels,footnotes,defaults,metadata,mathinfos,embedinfos,
                 citestyle,sanitize,bench,verbose,mathStatic,highlight,starBold,sandbox,prettyAlign,
                 xfmtCmd,xfmtEscape,xfmtLink,xfmtFootnote,xfmtTable,
                 xfmtEnv, xfmtCodePlain, /* xfmtCodeHilite, */ 
                 xfmtCodeToken, xfmtLineInfo, xfmtCodeTable, 
                 xfmtMathCmd, xfmtMathEnv,
                 fmt )
}

pub fun sanitize( contxt : inlineContext ) : bool {
  contxt.xsanitize
}


/* --------------------------------------
  Parse inline text elements 
---------------------------------------- */

pub fun logDataLine( attrs ) : () {
  match(attrs.hasKey("data-line")) {
    Nothing     -> ()
    Just(line)  -> logLocation(line)
  } 
}

// Parse _inline_ markdown elements and return formatted html
pub fun formatInline( contxt : inlineContext, txt : string, attrs : attrs = attrsNone ) : string
{
  val (linePrefix,lineNo) = parseLineInfo(attrs.lookupKey("data-line",""))
  formatInlineAcc(contxt,builder(), txt, lineNo, linePrefix )
}

pub fun parseLineInfo( lineInfo : string ) : (string,int) {
  match (lineInfo.find(rxDataLine)) {
    Nothing   -> ("",0)
    Just(cap) -> (cap.groups[1],cap.groups[2].parseIntDefault(0))
  } 
}
val rxDataLine = regex( r"^(.*:)?(\d+)$")


fun formatInlineAcc( contxt : inlineContext, acc : builder<h>, txt : string, 
                          lineNo : int, linePrefix : string ) : st<h> string
{
  if (txt=="") return acc.build
  val location  = linePrefix + lineNo.show
  val lineInfo  = if (lineNo <= 0) then "" else contxt.fmtLineInfo( location )
  if (lineNo > 0) then {
    val texLineInfo = "%mdk-data-line={" + location + "}"
    log("math-plain", texLineInfo)
    log("math-full", texLineInfo)
    log("aux", texLineInfo)
    logLocation(location)  // for warnings
  }
  val (s,next,_) = matchRules(contxt.grammar,contxt,txt,id)
  val newLineNo = if (lineNo <= 0) then 0 else lineNo + txt.substr(0,next).count("\n")
  formatInlineAcc(contxt, acc.append(lineInfo).append(s), txt.substr1(next), newLineNo, linePrefix )  
}



pub fun mathPreX( txt : string ) : string
{  
  val ignorearg = r"(?:mbox|begin|end|(?:text|math|varmath)(?:kw|id|rm|sf|tt|up|it|sl|sc|bf|md|lf|normal|bb|cal|scr|bbm|bbmss|bbmtt|ds|frak|swab|goth)?)"
  txt.replaceAll(regex(r"(\\" + ignorearg + r"{(?:[^\\}]|\\.)*}|\\[a-zA-Z@]+ *|\\[^a-z@])|^( +)|( +)|(\n)",multiline=True), fn(cap) {
        val n = cap.matched.length
        if (cap.groups.matchedOn(2)) then r"\mdmathindent{" + n.show + "}" 
        elif (cap.groups.matchedOn(3)) then string(n,'~') // r"\mdMathspace{" + cap.matched.length.show + "}"
        elif (cap.groups.matchedOn(4)) then "\\\\\n" // \\mdMathbr{}\n"
        else cap.matched
      })     
     .replaceAll(regex(r"(\\" + ignorearg + r"{(?:[^\\}]|\\.)*}|\\[a-z@]+(?![a-z@]))|#([a-z][a-z\d]*(?![a-z\d]))|([a-z][a-z\d]*(?![a-z\d]))|@([a-z][a-z\d]*(?![a-z\d]))", ignoreCase=True), fn(cap) {
        val grp = cap.groups.firstMatchedOn
        if (grp==2) then cap.groups[2]
        elif (grp < 2) then cap.matched
        else {
          val cmd = if (cap.groups.matchedOn(4)) then "mathkw" else "mathid"
          val captxt = cap.groups[grp]
          val (stem,digits) = match(captxt.find(regex(r"^([^\d]*(?:\d+[^\d]+)*)(\d*)$"))) {
                                Just(ccap) -> (ccap.groups[1],ccap.groups[2])
                                Nothing    -> (captxt,"")
                              }
          "\\" + cmd + "{" + stem + "}" + (if (digits=="") then "" else "_{" + digits + "}")
        } 
      })
}

pub fun mathPre( txt : string ) : string {
  "\\mathpre{" + txt.mathPreX + "}"
}

pub fun mathPreBlock( txt : string) : string
{
  val pre = mathPreX(txt)
  "\\begin{mdmathpre}%mdk\n" + pre + "\n\\end{mdmathpre}%mdk\n"     
}
