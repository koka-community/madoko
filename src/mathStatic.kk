/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Process math statically as LaTeX generated snippets
module mathStatic

import std/text/regex
import std/os/path
import std/data/dict
import common
import options
import latexFormatter
import storage
import mathParse


fun concurrent( tasks : list<(cont:(int) -> io ()) -> io ()>, continue : (int) -> io () ) : io () {
  if (tasks.isNil) return continue(0)

  var count   := tasks.length
  var lasterr := 0

  fun taskContinue( err : int ) {
    count := count - 1
    if (err != 0) then lasterr := err
    if (count<=0) then continue(lasterr)
  }

  tasks.foreach fn(task) {
    onFail( { count := count - 1 }, { task(taskContinue) } )
  }
}

fun mathHeader( xopts : options, mode : mathkind ) : string
{
  val mrender = xopts.math.getMathRender(mode)
  val deps    = ["% MathMode: " ++ mode.show,
                 "MathRender: " ++ mrender.show,
                 "MathDpi: " ++ xopts.math.dpi.show, // for convience to easily rebuild math we include it always
                 "MathEmbedLimit: " ++ xopts.math.embedLimit.show,
                 "MathScale: " ++ xopts.math.getMathScale(mrender).show,
                 "MathBaseline: " ++ xopts.math.baseline.show,
                 "MathDocClass: " ++ xopts.math.docClass,
                 "MathImgDir: " ++ xopts.math.imgDir,
                 "MathLatex: " ++ (if (mode.isPlain) then xopts.getMathLatex else xopts.getMathLatexFull),
                ] +
                (match(mrender) {
                  Svg -> [
                    "MathSvgFontFormat: " ++ xopts.math.svgFontFormat.show,
                    "MathSvgSharePaths: " ++ xopts.math.svgShare.show,
                    "MathSvgPrecision: " ++ xopts.math.svgPrec.show,
                    "MathSvgBBoxExact: " ++ xopts.math.svgBBoxExact.show,
                    "Dvisvg: " ++ xopts.math.dvisvg
                  ]
                  Png -> [
                   "Dvipng: " ++ xopts.math.dvipng,
                   "Convert: " ++ xopts.math.convert,
                   "Dvips: " ++ xopts.math.dvips,
                   "Ps2pdf: " ++ xopts.math.ps2pdf,
                  ]
                })

  deps.join(", ") ++ "\n"
}

fun mathContent( xopts : options, mode : mathkind, body : string = "" ) : string {
  val opts = if (xopts.math.docClass!="") then xopts(docClass=xopts.math.docClass) else xopts
  val xbody = "\\begin{mdSnippets}\n" ++ body ++ "\n\\end{mdSnippets}"
  opts.mathHeader(mode) ++ fmtLatexMathFull(mode,xbody,opts)
}

fun mathFormat( xopts : options, mode :mathkind, math : string, outName : string ) : (string,string,string)
{
  val texName = outName.appendStem("-math-" ++ mode.show).changeExt(".tex")
  val texFinalName = texName.changeExt(".final.tex")
  (texName,texFinalName,mathContent(xopts,mode,math))
}

pub alias runMathStaticFun
  = ( content : string, inName : string, outName : string,
      texNamePlain : string, texNameFull : string,
      plainPages : pages, fullPages : pages,
      oldMathPlain : string, oldMathFull : string,
      opts : options, continue : (maybe<(dict<mathinfo>,string)>) -> io () ) -> io ()


pub fun mathStatic( mathPlain : string, mathFull : string,
                            inName : string, outName : string, xopts : options, content : string,
                            runMathStatic : runMathStaticFun,
                            continue : (maybe<(dict<mathinfo>,string)>) -> io () ) : io ()
{
  val (texNamePlain,texNameFinalPlain,outMathPlain) = xopts.mathFormat(Plain,mathPlain,outName)
  val (texNameFull,texNameFinalFull,outMathFull) = xopts.mathFormat(Full,mathFull,outName)

  val oldMathPlain = readTextFileDef(texNameFinalPlain,xopts.mathContent(Plain,""),True)
  val oldMathFull = readTextFileDef(texNameFinalFull,xopts.mathContent(Full,""),True)

  /*
  if (outMathPlain != oldMathPlain) {
    trace("dvi differs!")
    trace("old: " ++ oldMathPlain)
    trace("new: " ++ outMathPlain)
  }
  */
  val dimxName = inName.changeExt(".dimx")
  if (fexistsSync(dimxName) && outMathPlain == oldMathPlain && outMathFull == oldMathFull && !(xopts.rebuild))
   then return continue(Nothing)

  xopts.print("rendering math.")
  if ((outMathPlain != oldMathPlain || xopts.rebuild || !fexistsSync(texNamePlain)) &&
      !(tryWriteTextFile(texNamePlain,outMathPlain))) then {
    xopts.printErr("error: unable to write: " ++ texNamePlain)
    return continue(Nothing)
  }
  if ((outMathFull != oldMathFull || xopts.rebuild || !fexistsSync(texNameFull)) && !(tryWriteTextFile(texNameFull,outMathFull))) then {
    xopts.printErr("error: unable to write: " ++ texNameFull)
    return continue(Nothing)
  }

  val rebuildPlain = oldMathPlain.unsnippet("old plain") != outMathPlain.unsnippet("new plain")
  val rebuildFull = oldMathFull.unsnippet("old full") != outMathFull.unsnippet("new full")
  // if (rebuildPlain || rebuildFull) trace("math rebuild")
  val plainPages = mathAnalyseChanged(outMathPlain,xopts.math.dim,xopts.rebuild || rebuildPlain)
  val fullPages = mathAnalyseChanged(outMathFull,xopts.math.dim,xopts.rebuild || rebuildFull)

  if (xopts.verbose>=1) then {
    if (plainPages.isNil && mathPlain.containsSnippet) then xopts.print("math unchanged (plain)")
    if (fullPages.isNil && mathFull.containsSnippet) then xopts.print("math unchanged (full)")
  }
  if (plainPages.isNil && fullPages.isNil) then {
    tryRename(texNamePlain,texNameFinalPlain); // save result to prevent rebuilds
    tryRename(texNameFull,texNameFinalFull);
    return continue(Nothing)
  }

  runMathStatic( content, inName, outName, texNamePlain, texNameFull,
                 plainPages, fullPages, oldMathPlain, oldMathFull,
                 xopts, continue )
}


fun getHeader( src : string ) : string
{
  match (src.find(rxHdr)) {
    Just(cap) -> cap.matched
    Nothing   -> ""
  }
}
val rxHdr = regex(r"^.*\n")

pub alias pages = list<(int,int)>

pub fun count( ps : pages ) : int {
  ps.foldl(0,fn(n,p) {
    n + (p.snd - p.fst + 1)
  })
}

fun range(lo,n) { if (lo<=0) then [] else [(lo,lo+n)] }

fun compress( pages : list<int>, lo : int = ~1, n : int = 0 ) : pages {
  match(pages) {
    Nil -> range(lo,n)
    Cons(p,ps) -> {
      if (p==lo+n+1)
       then compress(ps,lo,n+1)
       else range(lo,n) ++ compress(ps,p,0)
    }
  }
}

pub fun inside( page : int, pages : pages ) : bool {
  match(pages) {
    Nil -> False
    Cons((lo,hi),ps) -> {
      (lo <= page && page <= hi) || inside(page,ps)
    }
  }
}

fun mathAnalyseChanged( snippets : string, dim : dict<mathinfo>, rebuild : bool ) : pages
{
  val digests = snippets.findAll(rxDigest).list.mapIndexed( fn(idx,cap) { (idx+1,cap.groups[1]) })
  val maxPage = digests.length

  val pages = digests.concat fn(idigest) {
                val (current,digest) = idigest
                match(dim[digest]) {
                  Just(_)  | !rebuild -> []
                  _ -> [current]
                }
              }
  pages.compress
}
