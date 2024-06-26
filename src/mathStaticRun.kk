/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Process math statically as LaTeX generated snippets
module mathStaticRun

import std/text/regex
import std/os/path
import std/data/dict
import std/os/env
import common
import options
import storage
import process
import mathParse
import mathStatic
import runLatex

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


pub fun runMathStatic( content : string, inName: string, outName : string,
                        texNamePlain : string, texNameFull : string,
                        plainPages : pages, fullPages : pages,
                        oldMathPlain : string, oldMathFull : string,
                        opts0 : options, continue : (maybe<(dict<mathinfo>,string)>) -> io () ) : io ()
{
  opts0.checkDviSvgVersion(texNamePlain, texNameFull) fn(xopts) {
    mathSnippetsRender( Plain, xopts.math.getMathRender, xopts.getMathLatex, inName, texNamePlain, xopts, content, oldMathPlain, plainPages) fn(extplain) {
      if (extplain.isEmpty) return continue(Nothing)
      mathSnippetsRender( Full, xopts.math.getMathRenderFull, xopts.getMathLatexFull, inName, texNameFull, xopts, content, oldMathFull, fullPages) fn(extfull) {
        if (extfull.isEmpty) return continue(Nothing)
        mathToImg( texNamePlain.changeExt(extplain), texNameFull.changeExt(extfull), xopts, plainPages, fullPages ) fn(plainPageAdj,plainBboxAdj,fullPageAdj,fullBboxAdj) {
          mathDimAnalyse( outName.changeExt(".dimx"), xopts, plainPages, fullPages, texNamePlain, texNameFull, plainPageAdj, plainBboxAdj, fullPageAdj, fullBboxAdj) fn(mbmath) {
            if (mbmath.isJust) then {
              val texNameFinalPlain = texNamePlain.changeExt(".final.tex")
              val texNameFinalFull  = texNameFull.changeExt(".final.tex")
              tryRename(texNamePlain,texNameFinalPlain); // save result to prevent rebuilds
              tryRename(texNameFull,texNameFinalFull);
            }
            continue(mbmath)
          }
        }
      }
    }
  }
}

fun checkDviSvgVersion( opts : options, texNamePlain, texNameFull, cont : (options) -> io () ) : io () {
  if (opts.math.getMathRender.isSvg || opts.math.getMathRenderFull.isSvg) then {
    val dvisvgm = opts.math.dvisvg.quote
    system(dvisvgm ++ " --version", fn(err,stdout,stderr) {
      val version = match(stdout.find(rxVersion)) {
        Nothing -> 0
        Just(cap) -> {
          (100*cap.groups[1].parseIntDefault(0)) ++ cap.groups[2].parseIntDefault(0)
        }
      }
      if (err!=0 || version < 116) then {
        opts.printErr("warning: cannot use " ++ dvisvgm ++ "; ensure you have at least version 1.16")
        opts.printErr(" the latest version is available at: http://dvisvgm.bplaced.net/downloads")
        opts.printErr(" for Windows with TexLive 2016, see: madoko.net/doc/reference.html#dvisvgm")
        opts.printErr(" switching to use png images for math (instead of svg)")
        fileRenderPng(texNamePlain)
        fileRenderPng(texNameFull)
        cont(opts(math=(opts.math)(render=Just(Png),renderFull=Just(Png))))
      }
      else {
        cont(opts)
      }
    })
  }
  else {
    cont(opts)
  }
}
val rxVersion = regex(r"(\d+)(?:\.(\d+)?(?:\.\d*)?)?")

// fix up the tex file if we switch to PNG mode so PS specials are rendered correctly in TikZ/Pgf
fun fileRenderPng( fname : string ) : io () {
  val content = readTextFileDef(fname,"",False)
  if (content.notEmpty) then {
    val contentPng = content.replaceAll("\\mdmathrender{svg}","\\mdmathrender{png}")
    tryWriteTextFile(fname,contentPng)
    ()
  }
}


fun mathSnippetsRender( mode: mathkind, mrender : mathrender, texcmd: string,
                            srcName: string, texName : string, xopts : options,
                            content : string, oldMath : string,
                            pages : pages,
                            continue : (string) -> io () ) : io ()
{
  fun rendermsg(ext) {
    xopts.print( "running " ++ (texcmd.stemname ++ " on math...").fill(19) ++ "(" +
                  mode.show.fill(5) ++ " -> " ++ ext.substr(1) ++ " -> " ++ mrender.show ++ ")"  )
  }
  if (mrender.isSvg) then {
    // run for svg: we need a dvi or xdv
    val (texargs,dviext) = texcmd.texToDvi
    if (pages.isNil) then return continue(dviext)
    rendermsg(dviext)
    runLaTeX( srcName, texName, texcmd, texargs, xopts, content, "", 0, False, fn(err) {
      continue(if (err != 0) then "" else dviext)
    })
  }
  // run for png;
  elif (!(mode.isFull && texcmd.isPlainLatex)) then {
    // if we are not running in pdf with empty pdf latex
    val pdfext = if (texcmd.isPlainLatex) then ".dvi" else ".pdf"
    if (pages.isNil) then return continue(pdfext)
    rendermsg(pdfext)
    runLaTeX( srcName, texName, texcmd, "", xopts, content, "", 0, False, fn(err) {
      continue(if (err!=0) then "" else pdfext)
    })
  }
  else {
    // run for png; but we run plain latex so continue with dvips and ps2pdf
    if (pages.isNil) return continue(".pdf")
    // use dvips and ps2pdf to get a pdf
    val notfound = "set either the 'Math Mode: Mathjax' or the 'Latex: <cmd>' key in the metadata"
    val (texargs,dviext) = texcmd.texToDvi // induce it to produce .dvi
    rendermsg(dviext ++ " -> ps -> pdf")
    runLaTeX( srcName, texName, texcmd, texargs, xopts, content, notfound, 0, False, fn(err1) {
      if (err1!=0) then continue("")
      val dir = texName.dirname
      val stem = texName.stemname
      val dvipsCmd = xopts.math.dvips.quote ++ " -Ppdf -G0 " ++ (stem ++ ".dvi").quote
      val ps2pdfCmd = xopts.math.ps2pdf.quote ++ " " ++ (stem ++ ".ps").quote
      xopts.print("generating pdf from dvi...")
      xopts.print(">" ++ dvipsCmd, 3)
      system(dvipsCmd,fn(err,stdout,stderr) {
        if (err != 0) then {
          xopts.printErr("> " ++ dvipsCmd)
          xopts.printErr("error: failure while typesetting math: \n" ++ stdout ++ stderr)
          continue("")
        }
        else {
          xopts.print(">" ++ ps2pdfCmd, 3)
          system(ps2pdfCmd, fn(err2,stdout2,stderr2) {
            if (err2 != 0) then {
              xopts.printErr("> " ++ ps2pdfCmd)
              xopts.printErr("error: failure while typesetting math: \n" ++ stdout2 ++ stderr2)
              continue("")
            }
            else {
              continue(".pdf")
            }
          },xopts.processTimeout,dir)
        }
      },xopts.processTimeout,dir)
    })
  }
}

fun texToDvi( texcmd : string ) : (string,string) {
  if (texcmd.isXelatex)    then (" --no-pdf", ".xdv")
  elif (texcmd.isFulllatex) then (" --output-format=dvi", ".dvi")
  elif (texcmd.isLualatex) then (" --output-format=dvi", ".dvi")
                           else ("", ".dvi")
}

fun isXelatex( path : string ) : bool {
  path.stemname == "xelatex"
}

fun isLualatex( path : string ) : bool {
  path.stemname == "lualatex"
}

fun isFulllatex( path : string ) : bool {
  path.stemname == "pdflatex"
}

fun isPlainLatex( path : string ) : bool {
  path.stemname == "latex"
}


fun pagesShow( pages : pages ) : string {
  pages.map( fn(rng) {
    val (lo,hi) = rng
    lo.show ++ (if (lo>=hi) then "" else "-" ++ hi.show)
    }).join(",")
}

fun dvipngPages( pages : pages ) : string {
  pages.map( fn(rng) {
    val (lo,hi) = rng
    "-pp " ++ lo.show ++ (if (lo>=hi) then "" else "-" ++ hi.show)
    }).join(" ")
}

fun groupPages( gcount : int, count : int, cur : pages, acc : list<pages>, pages : pages ) : div list<pages> {
  match(pages) {
    Nil -> Cons(cur.reverse,acc).reverse
    Cons((lo,hi),rs) -> {
      val n = hi - lo + 1;
      val m = gcount - count;
      if (m >= n)
       then groupPages( gcount, count + n, Cons((lo,hi),cur), acc, rs)
      elif (m <= 0)
       then groupPages( gcount, 0, [], Cons(cur.reverse,acc), pages)
      else {
        val mid = lo + m - 1
        val r1 = (lo,mid)
        val r2 = (mid + 1, hi)
        groupPages( gcount, count + m, Cons(r1,cur), acc, Cons(r2,rs) )
      }
    }
  }
}

fun splitPages(pages : pages, concurrency : int) : list<pages> {
  val n   = pages.count
  val g   = if (n < 10 || concurrency <= 0) then 0 else ((n / concurrency) + 1);
  if (g <= 0) then [pages] else unsafeNoDiv{ groupPages(g,0,[],[],pages) }
}

fun dvisvgPages( pages : pages ) : string {
  "-p" ++ pages.map( fn(rng) {
      val (lo,hi) = rng
      lo.show ++ (if (lo>=hi) then "" else "-" ++ hi.show)
    }).join(",")
}

fun convertPages( pages : pages ) : string {
  "[" ++ pages.map( fn(rng) {
    val (lo,hi) = rng
    (lo - 1).show ++ (if (lo>=hi) then "" else "-" ++ (hi - 1).show)
    }).join(",") ++ "]"
}

fun convertSuffix( pages : pages ) : string {
  match(pages) {
    Cons((lo,hi)) | lo==hi -> "-" ++ (lo - 1).show
    _ -> ""
  }
}


fun mathToImg( namePlain : string, nameFull : string, xopts : options,
                      plainPages : pages, fullPages : pages,
                      continue : (int,double,int,double) -> io () ) : io ()
{
  val (plainconvCmd,plainPageAdj,plainBboxAdj)
    = mathConvImgCmd(Plain, namePlain, xopts.math.getMathRender, xopts.math, plainPages )
  val (fullconvCmd,fullPageAdj,fullBboxAdj)
    = mathConvImgCmd(Full, nameFull, xopts.math.getMathRenderFull, xopts.math, fullPages )

  // make sure the output directory exists
  val outDir = combine(namePlain.dirname,xopts.math.imgDir)
  if (!(fexistsSync(outDir))) then {
    xopts.print("create image directory: " ++ outDir)
    mkdirp(outDir)
  }

  mathCmdToImg( plainconvCmd, namePlain.dirname, Plain, plainPages, xopts, fn(err1) {
    mathCmdToImg( fullconvCmd, nameFull.dirname, Full, fullPages, xopts, fn(err2) {
      if (err1==0 && err2==0) then {
        continue(plainPageAdj,plainBboxAdj,fullPageAdj,fullBboxAdj)
      }
    })
  })
}


fun mathConvImgCmd( mode : mathkind, fname : string, mrender : mathrender, opts : mathoptions, pages : pages ) : (string,int,double) {
  val baseImg = combine(opts.imgDir,fname.stemname)
  match (mrender) {
    Svg -> {
      // extension should be dvi or xdv
      // add 0.2pt (~0.07mm of extra bounding box for better rendering of svg's)
      val fuzz = 0.2
      val cmd = splitPages(pages,opts.concurrency).map(fn(xpages) {
                  opts.dvisvg.quote ++
                    (if (opts.svgFontFormat=="" || opts.svgFontFormat=="none")
                      then " -n"
                     elif (opts.svgFontFormat=="svg")
                      then ""
                      else " --font-format=" ++ opts.svgFontFormat.quote) ++
                    (if (fuzz > 0.0) then " -b" ++ fuzz.showFixed(1) ++ "pt" else "") ++
                    (if (opts.svgBBoxExact) then " -e" else "") +
                    " -a -j -v3 -d" ++ opts.svgPrec.show ++ " " +
                    dvisvgPages(xpages) +
                    " -o " ++ (baseImg ++ "-%1p.svg").quote +
                    " " ++ fname.basename.quote
                }).join(";")
      (cmd,0,fuzz)
    }
    Png | fname.extname==".dvi" -> {
      val cmd = opts.dvipng.quote ++ " -T tight -z9 -bg Transparent" ++
                  " -D" ++ opts.dpi.show ++
                  " " ++ dvipngPages(pages) ++
                  " -o " ++ (baseImg ++ "-%d.png").quote ++
                  " " ++ fname.stemname.quote
      (cmd,0,0.0)
    }
    Png -> { // extension should be pdf
      val cmd = opts.convert.quote ++ " -trim -density " ++ opts.dpi.show ++ " " ++
                  (fname.basename ++ pages.convertPages).quote ++ " " ++
                  (baseImg ++ pages.convertSuffix ++ ".png").quote
      (cmd,~1,0.0)
    }
  }
}

fun mathCmdToImg( cmd : string, dir : string, mode : mathkind, pages : pages, xopts : options,
                       continue : (int) -> io () ) : io ()
{
  if (pages.isNil) return continue(0)

  xopts.print("generating math images...  (" ++ mode.show.fill(5) ++ ") (" ++ pages.pagesShow ++ ") (concurrency " ++ xopts.math.concurrency.show ++ ")")
  xopts.print("> " ++ cmd,3)
  system(cmd,fn(err2,stdout2,stderr2) {
    //trace("done system cmd")
    val output = stdout2 ++ stderr2
    if (err2 != 0) then {
      xopts.printErr("> " ++ cmd)
      xopts.printErr("error: failure while typesetting math: \n" ++ output)
      if (output.contains("Invalid Parameter -")) then {
        xopts.printErr("hint: perhaps you forgot to install ImageMagick?\n      (http://www.imagemagick.org/script/binary-releases.php)")
      }
      continue( if (output.contains(rxPSWarning)) then 0 else err2 )
    }
    else {
      if (xopts.verbose >= 4) then xopts.print(output)
      continue(0)
    }
  },xopts.processTimeout,dir)
}
val rxPSWarning = regex(r"^(warning: .*\r\n)+$",ignoreCase=True)


fun mathDimAnalyse( dimxName : string, xopts : options, plainPages : pages, fullPages : pages,
                         texNamePlain : string, texNameFull : string,
                         plainPageAdj : int, plainBboxAdj : double,
                         fullPageAdj : int, fullBboxAdj : double,
                         continue : (maybe<(dict<mathinfo>,string)>) -> io () ) : io () {
  xopts.print("analyse and embed math images.")
  val dims2 = extendDim(plainPages, fullPages, texNamePlain, texNameFull, plainPageAdj, plainBboxAdj, fullPageAdj, fullBboxAdj, dimxName, xopts )
  val (mdim2,svgdefs,msg) = dims2.parseMathDim(xopts.math)
  if (msg.bool) then xopts.print(msg)
  mathImageGC(mdim2,xopts.math.dim,dimxName.dirname)
  continue( Just((mdim2,svgdefs)) )
}

fun mathImageGC( newDim : dict<mathinfo>, oldDim : dict<mathinfo>, outDir : string ) : io ()
{
  oldDim.list.foreach fn(kv) {
    val (digest,mi) = kv
    match(newDim[digest]) {
      Just -> ()
      Nothing -> {
        val imageFile = combine(outDir,mi.imageName)
        tryUnlinkSync(imageFile)
      }
    }
  }
}

fun extendDim( plainPages : pages, fullPages : pages,
                    texNamePlain : string, texNameFull : string,
                     plainPageAdj : int, plainBboxAdj : double,
                     fullPageAdj : int, fullBboxAdj : double,
                     dimxFile : string, opts : options  ) : io string
{
  var imageSize := 0
  var imageCount := 0
  var embedSize := 0
  var embedCount := 0
  val dim = opts.math.dim

  fun dimLine( render:mathrender, mode : mathkind, fname : string,
                    pages : pages, pageAdj : int, bboxAdj : double, line : string )
  {
    match(line.find(rxDimLine)) {
      Nothing   -> line
      Just(cap) -> {
        val pageNo = cap.groups[2].parseInt.maybe(0,id)
        val digest = cap.groups[3]
        val imageStem = fname.stemname ++ "-" ++ (pageNo ++ pageAdj).show
        val imageName = combine(opts.math.imgDir, imageStem.changeExt(render.show) )
        val imageFile = combine(dimxFile.dirname,imageName)
        //trace("read image: " ++ pageNo.show ++ ": " ++ imageFile ++ ": " ++ imageFile)

        val (iwidth,iheight,size,embed)
          = match(dim[digest]) {
              Just(mi) | !(pageNo.inside(pages))
                -> {
                  //trace("known image: " ++ pageNo.show ++ ": " ++ imageFile ++ ": " ++ digest)
                  (mi.iwidth,mi.iheight,mi.size,mi.originalData)
                }
              _ -> {
                val res =
                  match(render) {
                    Png -> {
                      analyzeImagePng( imageFile, opts )
                    }
                    Svg -> {
                      analyzeImageSvg( imageFile, opts, mode, digest )
                    }
                  }
                val imageDigestFile = combine(imageFile.dirname,"math-" ++ digest ++ imageFile.extname)
                tryUnlinkSync(imageDigestFile)
                if (res.field4=="" && res.thd>0) then {
                  // give robust name
                  rename(imageFile,imageDigestFile)
                }
                else {
                  tryUnlinkSync(imageFile) // delete the image
                }
                res
              }
            }

        if (embed == "") then {
          imageSize  := imageSize + size
          imageCount := imageCount + 1
        }
        else {
          embedSize  := embedSize + size
          embedCount := embedCount + 1
        }
        cap.groups[1] ++ "," ++ iwidth.show ++ "pt," ++ iheight.show ++ "pt," ++ bboxAdj.show ++ "pt," ++
          size.show ++ "," ++ render.showMime ++ (if (embed=="") then "" else (", " ++ embed))
      }
    }
  }

  val plainDims = readTextFileDef(texNamePlain.changeExt(".dim"),"")
  val fullDims  = readTextFileDef(texNameFull.changeExt(".dim"),"")
  val dimsx   = plainDims.lines.list.map( fn(line) {
                  dimLine(opts.math.getMathRender,Plain,texNamePlain,plainPages,plainPageAdj,plainBboxAdj,line) }) +
                fullDims.lines.list.map( fn(line) {
                  dimLine(opts.math.getMathRenderFull,Full,texNameFull,fullPages,fullPageAdj,fullBboxAdj, line) })

  val txt = dimsx.join("\n")
  tryWriteTextFile( dimxFile, txt )
  if (opts.verbose >= 2) then {
    val totalCount = imageCount + embedCount
    val totalSize = imageSize + embedSize
    opts.print(" math images  : " ++ imageCount.show.align(4) ++ " in " ++ imageSize.showSize, 2 )
    opts.print(" math embedded: " ++ embedCount.show.align(4) ++ " in " ++ embedSize.showSize, 2 )
    opts.print(" math total   : " ++ totalCount.show.align(4) ++ " in " ++ totalSize.showSize, 2 )
  }
  txt
}

fun analyzeImagePng( imageFile, opts : options ) : io (double, double, int, string ) {
  match( tryReadFileSync( imageFile )) {
    Nothing   -> {
      opts.printErr("error: cannot read: " ++ imageFile)
      (0.0,0.0,0,"") // should not happen?
    }
    Just(buf) -> {
      val base64  = buf.toBase64()
      val pxwidth = buf.readInt4(16,True)
      val pxheight= buf.readInt4(20,True)

      val ppt     = (if (opts.math.dpi > 0) then opts.math.dpi.double else 72.27) / 72.27
      val iheight = pxheight.double / ppt
      val iwidth  = pxwidth.double / ppt

      //trace("image " ++ imageFile ++ ": " ++ pxwidth.show ++ "," ++ pxheight.show)
      val pngprefix = "data:image/png;base64,"

      val embed = if (base64!="" && base64.length + pngprefix.length < opts.math.embedLimit)
                    then pngprefix ++ base64 else ""
      //trace("embed: " ++ embed.length.show ++ ", " ++ opts.math.embedLimit.show)
      val size = if (embed.isEmpty) then buf.length else embed.length
      (iwidth,iheight,size,embed)
    }
  }
}

fun analyzeImageSvg( imageFile, opts : options, mode : mathkind, digest : string ) : io (double, double, int, string ) {
  match( tryReadTextFile( imageFile )) {
    Left   -> {
      opts.printErr("error: cannot read: " ++ imageFile)
      (0.0,0.0,0,"") // should not happen?
    }
    Right(svg1) -> {
      val (iheight,svg2) = svg1.svgExtractDim(rxSvgHeight)
      val (iwidth,svg3)  = svg2.svgExtractDim(rxSvgWidth)
      val svg            = svg3.svgCompress()
      val encoded        = "data:image/svg+xml;charset=utf8," ++ svg.encodeGlyphIds(mode).scopeStyles(digest)
      //trace("svg: " ++ imageFile ++ ", height: " ++ iheight.show ++ ", width: " ++ iwidth.show)
      val embed = if (encoded.length < opts.math.embedLimit) then encoded else ""
      //trace("embed: " ++ embed.length.show ++ ", " ++ opts.math.embedLimit.show)
      val size  = if (embed.isEmpty) then svg.length else embed.length
      (iwidth,iheight,size,embed)
    }
  }
}


// The following routines depend quite a bit on the particular dvisvgm output... :-(

// In order for glyphs to not be shared across pdf/dvi runs, we need to prefix
// identifiers so they are distinct and do not become shared paths.
// Glyph id's are of the form "g<fontid>-<charid>"
fun encodeGlyphIds( svg : string, mode : mathkind ) : string {
  if (mode.isPlain) return svg
  svg.replaceAll( rxSvgId, fn(cap) { cap.matched ++ mode.show } )
}
val rxSvgId = regex(r#"\b(id=['"](?:g)|xlink:href=['"]#g)(?=\d)"#)

// Scope CSS styles inside an SVG generated image such that we
// can embed multiple inside one HTML file. We use first 6 letters of
// the digest to uniquely name the SVG group from `page<no>` to `g-<digest>`.
fun scopeStyles( svg : string, digest : string ) :string {
  val groupId = "math-" ++ digest.substr(0,6)
  val pre     = "#" ++ groupId
  svg.replaceAll( rxSvgTextStyle, pre ++ " $&" ).replace( rxSvgGroupId, "$1" ++ groupId )
}
val rxSvgTextStyle = regex(r"\btext\.f\d+\s*\{\s*font")
val rxSvgGroupId   = regex(r#"(<g\s+id=['"])page\d+"#)

// Remove unnecessary parts of an svg to reduce the size (important since there
// can be thousands in math-heavy documents)
fun svgCompress( svg : string ) : string {
  svg.replaceAll(rxComment,"").replaceAll(rxNl,"").replaceAll(rxSpaces," ").trim
}
val rxNl      = regex(r"( *\r?\n)+(?=[ <])")
val rxSpaces  = regex(r"\s+")
val rxComment = regex(r"<!--[\s\S]*?-->|<\?xml[\s\S]*?\?>|\bversion='1.1'|\bxmlns='http://www.w3.org/2000/svg'|\bxmlns:xlink='http://www.w3.org/1999/xlink'")


fun svgExtractDim( svg : string, rx : regex ) : (double, string) {
  match(svg.find(rx)) {
    Nothing -> (0.0, svg)
    Just(cap) -> (dimension(cap.groups[1],cap.groups[2]), svg.substr(0,cap.index) ++ svg.substr(cap.next))
  }
}

val rxSvgHeight = regex(r"\bheight='(\d+)(?:\.(\d+))?(pt)?'")
val rxSvgWidth  = regex(r"\bwidth='(\d+)(?:\.(\d+))?(pt)?'")
