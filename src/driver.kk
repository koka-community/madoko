/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Main Madoko driver: provides files etc. and calls madoko.markdown
module driver

import std/text/regex
import std/os/path
import std/data/dict
import std/time/date
import common
import options
import metadata
import madoko
import block    // for lineMap
import storage
import hilite
import mathParse
import mathStatic
import texParser
import includes
import bibliography

pub struct runners(
  runPdfLatex : ( srcFile : string, texFile : string, opts : options, content : string, continue : (int) -> io () ) -> io (),
  runBibtex : ( bibFiles : list<string>, opts : options, continue : bool -> io ()) -> io (),
  runMathStatic : runMathStaticFun,
  runZip : ( files : list<string>, zipFile : string, opts : options, continue : bool -> io () ) -> io ()
)

val standardTexStyles = ["ellipse.sty","options.sty","longbox.sty","longfbox.sty","madoko2.sty"]

pub fun processContent( inName : string, outName : string, content : string,
                          opts : commandOptions, firstTime : bool = False,
                          runners : runners,
                          continue : (output:string,inputName:string,outputName:string,options:options) -> io () ) : io ()
{
  if (opts.options.sandbox) then enforceSandbox()
  if (opts.convertTex) then {
    val output = content.parseTex(ignore=False)
    writeTextFileSync(outName,output)
    return continue( output, inName, outName, opts.options );
  }

  val styleDir = opts.installDir ++ "/../styles"
  val searchDirs = [inName.dirname,outName.dirname,styleDir]
  val opts0  = if (inName.endsWith(".xmp.html") || inName.endsWith(".xmp"))
                then (opts.options)(xmp = True,full = opts.options.full.maybe(Just(False),Just)) else opts.options
  content.include(False, inName, outName, searchDirs, opts0) fn(icontent0,lmap) {
    // remove madoko comments
    val icontent = icontent0.removeMadokoComments
    // set up options

    val date   = now()
    val opts1  = opts0(lineMap=lmap,
                       processTimeout=if (opts0.sandbox) then 120000 else opts0.processTimeout,
                       metadata=opts0.metadata
                       ++ [("docname",inName.stemname),("filename",inName)]
                       ++ [("madoko-version",opts0.version)]
                       ++ [("date",date.isoLocalDate),("time",date.isoLocalTime.substr(0,5)),
                          ("year",date.year.show),("month",date.month.show2),("day",date.day.show2),
                          ("hours",date.hours.show2),("minutes",date.minutes.show2),("seconds",date.seconds.show2)] )

    // extract default cite-style if it exists
    val opts2  = opts1.extractCitestyle(outName)

    val mmopts = if (opts2.xmp)
                  then opts2.parseMeta( FmtHtml, icontent.normalizeSource.extractFirstXmp ).fst
                  else opts2.parseMeta( FmtHtml, icontent.normalizeSource ).fst  // get bibdata,bibstyle,mathimg

    // always read dims: even in dynamic mode some pdf math may exist
    val dims = if (mmopts.rebuild) then "" else outName.changeExt(".dimx").readTextFileDef("",False)
    val (mdim,svgdefs,_) = dims.parseMathDim(mmopts.math)

    val xopts  = opts2(math=(opts2.math)(dim=mdim,svgDefs=svgdefs))
    val mopts  = mmopts(math=(mmopts.math)(dim=mdim,svgDefs=svgdefs))

    // register languages for highlighting
    registerColorizers(mopts, searchDirs, icontent);

    // copy early since async latex may start for math
    if (mopts.copyStyles) then { // && !(xopts.sandbox) // allow even in sandbox
      // if (mopts.embedLimit < 16*1024) {  // only copy standard css style if it will not be embedded
      tryCopyTextFileFromNoSandboxTo( "madoko.css", styleDir, outName.dirname )
      // }
      if (xopts.tex || mopts.math.mode.isStatic) then { // only copy style files if generating tex or if math is static
        val isTex2  = match(mopts.metadata.find( fn(md) { md.fst == "tex2" } )) {
                        Just(md) -> md.snd.toLower == "true"
                        _ -> False
                      }
        val files = if (isTex2)
                     then standardTexStyles
                     else ["css.sty","madoko.sty"]
        files.foreach fn(fname) {
          tryCopyTextFileFromNoSandboxTo(fname, styleDir, outName.dirname )
        }
      }
    }

    process( inName, outName, searchDirs, content, icontent, xopts, mopts, firstTime, runners)
      fn() {
        processContent(inName,outName,content,opts,False,runners,continue) // redo!
      }
      fn(html) {
        continue(html,inName,outName,mopts)
      }
  }
}

fun extractFirstXmp( s : string ) : string {
  match (s.find(rxXmp)) {
    Nothing -> ""
    Just(cap) -> cap.groups[1]
  }
}
val rxXmp = regex(r"<xmp\b.*?>([\s\S]*?)</xmp>")

val rxCurDir = regex(r"^(\.)(?=[\\/])")

fun process( inName : string, outName : string, searchDirs : list<string>,
                  content : string, icontent : string,
                  xopts0 : options, mopts : options, firstTime : bool, runners : runners,
                  redo : () -> io (),
                  continue : (string) -> io () ) : io ()
{
  fun genTexZip(outTexName:string, refers:list<string>) {
    if (mopts.texzip) then {
      createTexZip( inName, outTexName, refers, mopts, runners, fn(err) { () } )
    }
  }

  fun genPdf(outTexName:string, refers:list<string>) {
    if (mopts.pdf) then {
      (runners.runPdfLatex)( inName, outTexName, mopts, content, fn(err) {
        if (err==0) then genTexZip(outTexName, refers) else ()
      })
    }
    else () // cannot zip without pdf
  }

  fun embedFiles( opts: options, files : list<string>, html0 : string ) : io (options,string) {
    if (files.length == 0) return (opts,html0);

    val infos = files.concat fn(fname) {
                  val mime = mimeFromExt(fname);
                  val data = if (mime.startsWith("text/"))
                                then searchReadTextFileDef(fname,"",searchDirs,"",False)
                              elif (mime.startsWith("image/"))
                                then {
                                  //trace("embed image: " ++ fname)
                                  val img = readBase64FileDef(combine(inName.dirname,fname),"",False)
                                  if (img != "") then "data:" ++ mime ++ ";base64," ++ img else img
                                }
                              else ""

                  // write the file to the out directory
                  if (data != "" && (data.length > mopts.embedLimit)) then {
                    val newName = combine(outName.dirname,fname) // assumes just relative embed names!
                    if (newName.normalize != fname.normalize) then {
                      //trace("copying: " ++ fname ++ " to " ++ newName)
                      mkdirp(newName.dirname)
                      if (mime.startsWith("text/")) then {
                        tryWriteTextFile(newName,data);
                      }
                      else {
                        tryWriteBase64File(newName,data.replace(regex(r"^data:[^;]*;base64,"),""));
                      }
                      ()
                    }
                  }

                  // embed
                  if (data != "" && data.length < mopts.embedLimit)
                   then [(fname,Embedinfo(fname,data))]
                  else {
                    if (fname!="" && mopts.embedLimit > 0) then {
                      mopts.printErr("warning: unable to embed: " ++ fname +
                                       (if (data.length > 0) then " (too large)" else " (does not exist)"))
                    }
                    []
                  }
                }
    if (infos.length == 0) return (opts,html0)

    val newopts = opts(embedinfos = opts.embedinfos ++ infos.dict, verbose=min(opts.verbose,1))
    val newhtml = markdown(icontent,newopts).fst
    (newopts,newhtml)
  }

  fun phaseHtml()
  {
    // markdown to html
    val (fileEmbed,(mathPlain,(mathFull,(warns0,(logs, (html0,_fullOptions)))))) =
                              withLog("embed") {
                               withLogCompress("math-plain") {
                                withLogCompress("math-full") {
                                 withLogCompress("warning") {
                                  withLogCompress("aux") {
                                   markdown(icontent,xopts0)
                                 }}}}}
    // write an aux file
    val bibChanged =
      if (logs == "" || !logs.contains("\\citation{")) then []
      else {
        /*
        if (mopts.bibStyle.extname != "" || mopts.bibStyle.dirname != "") {
          // copy bst file
          tryCopyTextFileFromTo( mopts.bibStyle.basename, mopts.bibStyle.dirname, outName.dirname )
          ()
        }
        */
        writeCitationsData( logs, outName, searchDirs, mopts.bib.splitPaths, mopts )
      }

    // run bibtex?
    if (!bibChanged.isNil && firstTime && mopts.bibtex!="") then {
      if (mopts.bib.bool) then {
        genBibtex( runners.runBibtex, bibChanged, outName.dirname, searchDirs, mopts ) fn(err) {
          redo()
        }
      }
      else {
        mopts.printErr("warning: found citations but no bibliography file is specified.\n Hint: specify 'Bibliography: <myfile>.bib' in the metadata.")
        // mopts.printErr("citations:\n" ++ logs.indent(2), 2)
        redo() // TODO: restructure to not call redo
      }
    }
    else {
      // do embedding
      val (xopts,html) = embedFiles(xopts0,fileEmbed.split("\n").list,html0);

      // write html result
      if (!(tryWriteTextFile(outName,html))) then {
        mopts.printErr("error: unable to write: " ++ outName)
      }

      // show warnings
      val warns = fixWarnings(warns0)
      if (warns != "") then {
        log("stdout",warns)
        if (mopts.verbose >= 1) then {
          print(warns)
        }
      }

      // generate tex
      val outTexName = outName.changeExt(".tex")
      val texRefers =
        if (!mopts.tex) then [] else {
          if (mopts.verbose >= 1) then println("process: " ++ inName ++ " -> " ++ outTexName )
          val (texwarns, (texFiles, (texRefer, tex)))
                = withLog("texwarning", {
                    withLog("files", {
                      withLog("filesRefer", {
                       markdown(icontent,xopts,FmtTex).fst
                      })
                    })
                  })
          if (texwarns != "") then {
            log("stdout",texwarns)
            if (mopts.verbose>=1) then {
              print(texwarns)
            }
          }
          if (!(tryWriteTextFile(outTexName,tex))) then {
            mopts.printErr("error: unable to write: " ++ outTexName)
          }
          texFiles.split("\n").list ++ texRefer.split("\n").list
        }

      // possibly typeset math using latex
      if ((mathPlain.containsSnippet && mopts.math.mode.isStatic) || mathFull.containsSnippet) then {
        if (mopts.verbose>=2 && mopts.math.mode.isDynamic && mathFull.containsSnippet) then {
          mopts.print("warning: dynamic math mode but some math requires pdf",2)
        }
        mathStatic( mathPlain, mathFull, inName, outName, mopts, content, runners.runMathStatic ) fn(mbmres) {
          match(mbmres) {
            Just((mdim2,svgdefs)) -> {
              // write html again
              mopts.print("re-aligning math in HTML.")

              val html2 = markdown(icontent,xopts(math=(xopts.math)(dim=mdim2,svgDefs=svgdefs))).fst
              if (!(tryWriteTextFile(outName,html2))) then {
                mopts.printErr("error: unable to write: " ++ outName)
              }
            }
            Nothing -> ()
          }
          //if (mopts.verbose>=1) println("  done typesetting math.")
          genPdf(outTexName,texRefers)
        }
      }
      else {
        genPdf(outTexName,texRefers)
      }

      continue(html)
    }
  }

  phaseHtml()
}

// Create a Tex zip
fun createTexZip( inName : string, outTexName : string, refers : list<string>, mopts : options, runners : runners, cont ) : io () {
  val namesRefer = refers.map fn(fname) {
    if (fname != "" && fname.relative && fname.extname != ".bib") then {
      val outName = combine(outTexName.dirname,fname).normalize
      if (outName != fname) then {
        trace("refer: " ++ fname ++ " to " ++ outName)
        mkdirp(outName.dirname)
        copyFile(fname,outName)
        Just(outName)
      }
      else Nothing
    }
    else Nothing
  }
  val names = [outTexName,outTexName.changeExt(".pdf")] ++ standardTexStyles ++ namesRefer.concatMaybe ++ [outTexName.changeExt(".bbl")]
  (runners.runZip)( names, outTexName.changeExt(".zip"), mopts, cont )
}

// Fixup locations in warnings:
fun fixWarnings(txt : string) : string {
  var location := "";
  val hist = mdict();
  val ls = txt.lines.list.map fn(line) {
    match(line.find(rxLocation)) {
      Nothing -> {
        match(line.find(rxWarning)) {
          Nothing   -> Just(line ++ "\n")
          Just(cap) -> {
            val count = hist[line].mbint
            hist[line] := count+1
            if (count == 4)
             then Just("warning: " ++ location ++ " ignoring from now on:" ++ line ++ "\n")
            elif (count > 4)
             then Nothing
             else Just(cap.groups[1] ++ location ++ cap.groups[2] ++ "\n")
          }
        }
      }
      Just(cap) -> {
        location := cap.groups[1] ++ ":"
        Nothing
      }
    }
  }
  ls.concatMaybe.join
}
val rxLocation = regex(r"^\s*location:(.*)",ignoreCase=True)
val rxWarning  = regex(r"^(\s*(?:error|warning):)(.*)",ignoreCase=True)

// Remove <!--madoko comments
fun removeMadokoComments( txt : string ) : string {
  txt.replaceAll( rxMadokoComment, "\n$1\n")
}
val rxMadokoComment = regex(r"^<!--madoko[ \t\r]*\n([\s\S]*?)^-->[ \t\r]*\n", ignoreCase=True, multiline=True)

// Register colorizers
fun registerColorizers( opts : options, searchDirs : list<string>, content : string ) : io ()
{
  val searchDirsEx = searchDirs.concat( fn(dir) { [dir,combine(dir,"lang")] } )
  val registered = mdict()
  val langs1 = opts.hilitelang.split(";").list
  val langs2 = content.findAll(regex(r"(?:^ *```+ *|\blanguage\s*[:=])([\w\-\/]+)\b",multiline=True)).list.map(fn(cap) { cap.groups[1].basename })
  val langs  = (langs1 ++ langs2).map(toLower)
  langs.foreach fn(lang) {
    match (registered[lang]) {
      Just -> ()
      Nothing -> {
        registered[lang] := True
        if (lang != "") then {
          match( trySearchReadTextFile(lang,searchDirsEx,".json")) {
            Nothing -> {
              log("files", changeExt(lang,".json"))
              opts.printErr("warning: unable to read language definition: " ++ lang)
            }
            Just((_,definition)) -> {
              val langName = lang.basename.noext.toLower
              //trace("register language: " ++ langName ++ ":\n" ++ definition )
              registerLanguage(langName,definition)
            }
          }
        }
      }
    }
  }
}

pub fun outputName( inputName : string, options : commandOptions ) : string {
  val noextName = if (inputName.endsWith(".xmp.html")) then inputName.substr(0,inputName.length - 9) else inputName.noext
  val outName = if (options.convertTex) then inputName ++ ".mdk" else noextName ++ ".html"
  if (options.outputDir=="")
   then outName
   else options.outputDir ++ "/" ++ outName.basename
}

fun tryCopyTextFileFromNoSandboxTo( fname, srcDir, outDir ) {
  val inName = combine(srcDir,fname)
  val outName = combine(outDir,fname)
  catch {
    val txt = readTextFileNoSandbox( inName )
    tryWriteTextFile(outName,txt)
    ()
  }
  fn(exn) { () }
}


pub fun withLogCompress( name: string, action : () -> <ndet|e> a ) : <ndet|e> (string,a) {
  val (log,x) = withLog(name,action)
  (log.replaceAll(rxDataLinesPre,""), x)
}

val rxDataLinesPre = regex("(?:\r?\n%mdk-data-line=.*(?=\r?\n%mdk-data-line))+")
