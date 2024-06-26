/*---------------------------------------------------------------------------
  Copyright 2015 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Running latex and bibtex
module runLatex

import std/text/regex
import std/os/path
import std/data/dict
import std/os/env
import common
import options
import storage
import process


// normalize a file name: needed for latex 
fun norm( fname : string ) : string {
  fname.replaceAll("\\", "/");
}

pub fun runZip( files : list<string>, zipFile : string, opts : options, continue : (bool) -> <io|e> () ) : <io|e> () {
  opts.print("running zip to generate tex zip...")
  val outdir    = zipFile.dirname
  fun adjust( fname ) {
    val name = if (fname.startsWith(outdir)) then fname.substr(outdir.length + 1) else fname
    name.checkSandbox.quote
  }
  val zipCmd = opts.zip.quote ++ " -9 " ++ zipFile.adjust ++ " " ++ files.map(adjust).join(" ")
  tryUnlinkSync(zipFile.checkSandbox)
  opts.print("> " ++ zipCmd)
  system(zipCmd, fn(err:int,stdout:string,stderr:string) {
    if (err!=0) then {
      opts.printErr("error while running: > " ++ zipCmd)
      val allout = stdout + stderr
      opts.printErr("error: zip:\n" ++ allout.indent(2))
    }
    else {
      if(opts.verbose>=1 && !(stdout=="" && stderr=="")) then opts.printErr(stdout + stderr)
    }
    continue(err!=0)
  },opts.processTimeout,outdir)
}

pub fun runBibtex( bibFiles : list<string>, opts : options, continue : bool -> <io|e> ()) : <io|e> () {
  match(bibFiles) {
    Nil -> continue(False)
    Cons(bibFile,rest) -> {
      runBibtex1( bibFile, opts, fn(err) {
        runBibtex( rest, opts, if (err) then fn(_) { continue(True) } else continue )
      })
    }
  }
}

pub fun runBibtex1( bibFile : string, opts : options, continue : bool -> <io|e> ()) : <io|e> () {
  opts.print("running bibtex to generate bibliography...")
  val xbibFile = checkSandbox(bibFile)
  val bibtexCmd = opts.bibtex.quote ++ " " ++ xbibFile.basename.quote
  opts.print("> " ++ bibtexCmd,3)
  system(bibtexCmd, fn(err:int,stdout:string,stderr:string) {
    if (err!=0) then {
      opts.printErr("error while running: > " ++ bibtexCmd)
      system(opts.bibtex.quote ++ " -version") fn(errx:int,stdoutx,stderrx) {
        if (errx!=0) then {
          opts.printErr("error: could not find bibtex: \"" ++ bibtexCmd ++ "\"\n" ++
                        "\n  hint: Set the 'BibTeX: ...' key or give the '--bib=<cmd>' command line option.\n")
        }
        else {
          val allout = stdout + stderr
          opts.printErr("error: bibtex:\n" ++ allout.indent(2))
          match (allout.find(rxBibtexNoStyle)) {
            Nothing -> ()
            Just(cap) -> opts.printErr("error: source line: " ++ cap.groups[3] ++ ":" ++ cap.groups[2] ++ 
                                        "\n  cannot find bibliography style file '" ++ cap.groups[1] ++ "'" ++
                                        "\n  hint: perhaps put the file in the document directory and use the" ++ 
                                        "\n        'Bib style: " ++ cap.groups[1].noext ++ ".bst' metadata (with the '.bst' extension).\n");
          }
          allout.findAll(rxBibtexError).foreach( fn(cap) {
            opts.printErr("error: source line: " ++ cap.groups[3] ++ ":" ++ cap.groups[2] +
                          "\n  " ++ (cap.groups[1] + cap.groups[4].unindent).indent(2) ++ "\n" )
          })
        }
        continue(True)
      }
    }
    else {
      if(opts.verbose>=1 && !(stdout=="" && stderr=="")) then opts.printErr(stdout + stderr)
      continue(False)
    }
  },opts.processTimeout,bibFile.dirname)
}

val rxBibtexLineinfo= r"---line *(\d+) *of file *(.*)"
val rxBibtexNoStyle = regex(r"^ *I couldn't open style file *(.*)\s*" ++ rxBibtexLineinfo, multiline=True)
val rxBibtexError   = regex(r"^ *(.+?)" ++ rxBibtexLineinfo ++ r"((?:\s*:.*)*)", multiline=True)

pub fun runPdfLaTeX( srcName : string, texFile : string, opts : options, content : string, continue : (int) -> io () ) {
  opts.print("running " ++ opts.getPdfLatex.stemname ++ " to generate pdf...")
  val notfound = "set the 'Pdf Latex: <cmd>' key in the metadata?"
  runLaTeX(srcName, texFile, opts.getPdfLatex, "", opts, content, notfound, 0, True, continue )  
}

val latexEnv = [
  ("max_print_line","1000"),
  ("error_line","250"),
  ("half_error_line","230"),
]

val latexSandboxEnv = [
  ("openin_any","p"),
  ("openout_any","p"),
  ("shell_escape","f"),
  ("parse_first_line","f"),
]

pub fun runLaTeX( srcFile : string, texFile : string, texCmd : string, extraArgs : string,
                    opts : options, 
                    content : string,
                    notfound : string,
                    runCount : int = 0,
                    showWarnings : bool = True,
                    continue : (err : int) -> io () )
{
  val dir = texFile.dirname.norm
  val latexCmd = texCmd.quote + 
                  (if (extraArgs.bool) then " " ++ extraArgs else "") ++ 
                  " --output-directory=" ++ (if (dir=="") then "." else dir).quote ++ 
                       " --interaction=batchmode" ++ // --max-print-line=1000" ++ 
                       (if (opts.sandbox) then " --no-parse-first-line --no-shell-escape" else "") ++ // note: also need `openin_any:p` and `openout_any:p`: pass through environment instead
                       " " ++ texFile.norm.quote 

  if (runCount==0 && opts.rebuild) then {
    tryUnlinkSync(texFile.changeExt(".aux"))
  }
  opts.print("> " ++ latexCmd,3)
  
  system(latexCmd, fn(err:int,stdout:string,stderr:string) {
    val logout = readTextFileDef(texFile.changeExt(".log"),"")
    if (err!=0) then {
      opts.printErr("error while running: \n> " ++ latexCmd)
      //trace("error code: " ++ err.show ++ "\n" ++ stdout + stderr)
      //println(stdout + stderr)
      system(texCmd.quote ++ " -version") fn(errx:int,stdoutx,stderrx) {
        if (errx!=0) then {
          opts.printErr("error: could not find program: \"" ++ texCmd ++ "\"")
          if (notfound != "") then opts.printErr(notfound)
        }
        else {
          val errmsg = "error: latex:\n" ++ stdout ++ stderr
          match(logout.find(rxLatexErr)) {
            Just(cap) -> match(cap.matched.findLatexLineNo) {
              Just( (texlineNo, texerr) ) -> {
                val texContent = readTextFileDef(texFile,"")
                //trace(logout.substr(cap.index-100))
                match(findLatexPackage(logout.substr(0,cap.index))) {
                  Just(pkg) -> opts.printErr("error: source line: " ++ pkg ++ ":" ++ texlineNo.show)
                  Nothing   -> match (content.findLatexLine(texlineNo,texContent)) {
                    Just(lineNo) -> opts.printErr("error: source line: " ++ lineNo)
                    Nothing -> ()
                  }
                }                  
                opts.printErr(nicifyLatexErr(texerr))
              }
              Nothing -> {
                //trace("could not find lineo")
                opts.printErr(errmsg)    
              }
            }
            Nothing -> {
              //trace("could not find error")
              opts.printErr(errmsg)              
            }
          } 
          opts.printErr("log written at: " ++ texFile.changeExt(".log"))
        }      
        continue(err)       
      }
    }
    else {
      if (runCount <= 2 && logout.contains(rxLatexRerun)) then {
        opts.print("rerun to resolve references...")
        runLaTeX( srcFile, texFile, texCmd, extraArgs, opts, content, notfound, runCount+1, showWarnings, continue)
      }
      else {
        if (showWarnings) then latexShowWarnings(texFile,logout,content,opts)
        continue(0)
      }
    }
   },
   opts.processTimeout,
   srcFile.dirname,
   std/env/env.list + latexEnv + (if (opts.sandbox) then latexSandboxEnv else [])
  )
} 
val rxLatexErr = regex(r"(?:^! LaTeX Error:.*|^\*\* ERROR .*|^(?:!|Runaway argument\?))[\s\S]*?(?=\r?\n\r?\n\r?\n|^\s*(?:Here is how much of \w*TeX's memory you used:|The control sequence))",multiline=True,ignoreCase=True)

val rxLatexRerun = regex(r"^((Package|Latex) .*?warning\b.*?|\(\w+\) +)Rerun\b",multiline=True,ignoreCase=True)

fun nicifyLatexErr( err :string) : string {
  match(err.find(rxLatexSubErr)) {
    Nothing   -> err
    Just(cap) -> cap.matched ++ "\n"
  }
}
val rxLatexSubErr = regex(r#"The font "[^"\n\r]*"" cannot be found\."#,multiline=True,ignoreCase=True)


fun findLatexLineNo( texerr : string ) : maybe<(int,string)> {
  match(texerr.find(rxLatexLineNum)) {
    Nothing   -> Nothing
    Just(cap) -> match( cap.groups[1].parseInt ) {
                   Nothing -> Nothing
                   Just(i) -> Just( (i, texerr.substr(0,cap.next)) )
                 }
  }
}
val rxLatexLineNum = regex(r"(?:^|\n)l\.(\d+) +[\s\S]*?(?=\r?\n\r?\n|$)")

fun findLatexLine( src : string, lineNo, texSrc : string ) : maybe<string> {
  val searchLines = texSrc.lines.list.take(lineNo - 1).reverse
  //trace("latex lineno: " ++ lineNo.show ++ "\n" ++ searchLines.join("\n") ++ "\n\n")
  findLatexLineData(0, searchLines )
}
val rxLatexEndSnippet = regex(r"\\end{md(Inline|Display)?Snippet}")

fun findLatexLineData( delta : int, lines : list<string> ) : maybe<string> {
  match(lines) {
    Nil -> Nothing
    Cons(line,rest) -> {
      match(line.find(rxLineData)) {
        Nothing -> {
          val newDelta = if (line.contains(rxEndComment)) then delta else delta+1
          findLatexLineData( newDelta, rest )
        }
        Just(cap) -> {
          val last = cap.groups[1].split(";").list.reverse.take(1).join()
          //trace(" found line info: " ++ cap.matched ++ ", last: " ++ last ++ ", delta: " ++ delta.show)
          match( last.find(rxLineNo) ) {
            Nothing -> Nothing
            Just(cap2) -> Just(cap2.groups[1]  + (cap2.groups[2].parseInt.maybe(0,id) + delta).show)
          }
        }
      }
    }
  }
}
val rxLineData    = regex( r"^(?:[^\\%]|\\.)*% *(?:mdk-)?data-line=\{([^\}]*)\} *$" )
val rxLineNo      = regex( r"^([^:]*:)?(\d+)$" )
val rxEndComment  = regex( r"^(?:[^\\%]|\\.)*%mdk.*$" )


fun findLatexPackage( logout : string, pkgs : list<string> = [] ) : maybe<string> {
  match(logout.find(rxPackageLine)) {
    Nothing -> {
      match(pkgs) {
        Cons -> Just(pkgs.reverse.join(";"))
        _    -> Nothing
      }
    }
    Just(cap) -> {
      val newpkgs = 
        if (cap.groups[6] != "") then {
          // loaded))
          pkgs.drop(cap.groups[6].count(")"))
        }
        else {
          val pkg = cap.groups[1] + cap.groups[4]
          val dropBefore = cap.groups[3].length
          val dropAfter  = cap.groups[2].length + cap.groups[5].length 
          //trace("flp: packages: " ++ pkgs.join(";"))
          //trace("     found: " ++ pkg ++ ", " ++ dropBefore.show ++ ", " ++ dropAfter.show)
          val pkgs0 = pkgs.drop(dropBefore)
          val pkgs1 = if (pkg.isEmpty) then pkgs0 else Cons(pkg,pkgs0)
          val pkgs2 = pkgs1.drop(dropAfter)
          pkgs2
        }
      findLatexPackage( logout.substr1(cap.next), newpkgs )
    }
  }
}

val rxPackage   = r"\((?:\./)?([^\)\n\r\t]+) *(?:(\)+) *)?"
val rxPackageEnd = r"(\)+) *(?:" ++ rxPackage ++ r")?"
val rxPackageEndLoaded = r"[^\(\r\n]*?((?: loaded\)+)+)"  // xypic package suffers from this
val rxPackageStart = rxPackage
val rxPackageLine = regex(r"^(?:\] *)?(?:" ++ rxPackageStart ++ "|" ++ rxPackageEnd ++ "|" ++ rxPackageEndLoaded ++ r")(?=$| *\[\d+(?:$|\]))", multiline=True)


pub fun latexStrip( s : string ) : string
{
  s.replaceAll(rxStrip,"")
}

val rxStrip = regex(r"(\\[\w/\-\r\n]*(\[[^\]\r\n]*\])?|\^\^.|'\w*|\}\{[lrct]\}|\]\{[^\]\r\n]*\}|[^a-zA-Z])+") // ;""!\*()/\+=/,~:

pub fun latexFindLineByMatch( texLine : string, source : string ) : maybe<string> {
  val stripLine = texLine.latexStrip.substr(0,16) // some arbitrary length... seems to work well in practice
  if (stripLine.length < 3) then Nothing else {
    match (source.findLines(stripLine)) {
      Cons(lineNo,rest) -> Just(lineNo.show + (if (rest.isNil) then "" else " (?)"))
      _ -> Nothing      
    }
    /*
    ilines = source.lines.list.mapIndexed(fn(idx,line) { (idx,line) })
    match(ilines.filter(fn(iline){ iline.snd.latexStrip.contains(stripLine) })) {
      Cons(iline,rest) -> Just((iline.fst+1).show + (if (rest.isNil) then "" else " (?)"))
      _ -> Nothing
    }
    */
  }
}

fun findLines( source : string, pat : string ) : list<int> {
  val slines  = source.lines.list.map(fn(line) { line.latexStrip })
  val slens   = slines.map(fn(s){ s.length })
  val offsets = findOffsets( slines.join, pat )
  offsets.map fn(ofs) {
    var total := 0
    var current := 1
    slens.foreachUntil fn(len) {
      total := total + len
      if (total > ofs) then return Just(current) 
      current := current + 1
      Nothing
    }
    current
  }
}

fun findOffsets( source : string, pat : string ) : list<int> {
  val i0 = source.indexOf(pat)
  val i1 = source.lastIndexOf(pat)
  if (i0 < 0) then []
  elif (i0 == i1) then [i0]
  else [i0,i1]
}

fun latexShowWarnings(texFile:string,logout:string, content:string,opts:options) : io () 
{
  if (opts.verbose<2) then {
    if (opts.verbose>=1) then {
      match(logout.find(rxLatexOutput)) {
        Just(cap) -> opts.print(cap.matched,1)
        Nothing -> ()
      }
    }
    return ()
  }

  val warnings = logout.findAll(rxLatexWarning).list.map(fn(cap) { (cap.index,cap.matched) })
  if (warnings.isNil) then return () 

  val texlines = readTextFileDef(texFile,"").lines
  println("")
  warnings.foreach fn(iw) {
    val (index,warning0) = iw
    val warning = warning0.replace(rxLatexBrackets,"")
    val warn = match(warning.find(rxLatexLine)) {
      Nothing   -> {
        // no line no: try to display page
        val pre = match(warning.find(rxLatexOutputActive)) { 
                Just -> {  // find a page
                  val page = match(logout.substr(0,index).findAll(rxLatexPage).list.reverse) {
                    Cons(pcap,_) -> (pcap.groups[1].parseInt.maybe(0,id)+1).show 
                    Nil -> "1"
                  }  
                  "> warning: page " ++ page ++ "\n"
                } 
                Nothing -> "" 
              }
        pre + warning
      }
      Just(cap) -> {
        val line = if (cap.groups[2].latexStrip != "") then cap.groups[2] 
                else {
                  val lineNo = cap.groups[1].parseInt.maybe(0,id)
                  texlines.latexFindLine(lineNo)
                }                
        val pre = match(latexFindLineByMatch(line,content)) {
          Nothing -> {
            if (opts.verbose >= 4) then opts.printErr("unable to find line: \n> " ++ line.latexStrip ++ "\n")
            ""
          }
          Just(srcLineNo) -> "> warning: source line: " ++ srcLineNo ++ "\n"
        }

        pre + warning + (if (cap.groups[2]=="" && line!="") then "\n> " ++ line.substr(0,74) else "")
      }
    }
    opts.printErr(warn ++ "\n")
  }
  match(logout.find(rxLatexOutput)) {
    Just(cap) -> opts.printErr(cap.matched)
    Nothing   -> if (warnings.isCons) then opts.printErr("end of latex warnings.")  
  }
}

val rxLatexLine = regex(r"lines?[\s:]*(\d+).*(?:\r?\n([\s\S]*))?") 
val rxLatexOutputActive = regex(r"\output is active\s*$") // only match single line 
val rxLatexPage = regex(r"\s\[(\d+)\s*\]")
val rxLatexOutput = regex(r"^Output written on .*", multiline=True)
val rxLatexBrackets = regex(r"(\s|[\[\]])+$")
val rxLatexWarning = regex(r"^(Overfull|Underfull|[\w ]*[Ww]arning:)[\s\S]*?\n *$", multiline=True)

fun latexFindLine( src : vector<string>, lineNo : int, direction : int = 0 ) : div string
{
  val line = latexGetLine(src,lineNo)
  if (line.contains(rxEnd) && direction <= 0) then {
    latexFindLine(src,lineNo - 1,~1)
  }
  elif (line.contains(rxBegin) && direction >= 0) then {
    latexFindLine(src,lineNo + 1,1)
  }
  else {
    line
  }
}

val rxEnd = regex(r"^\\end|^\s*(\\?\}\s*)*$",multiline=True)
val rxBegin = regex(r"^\\begin|^\s*(\\?\{})*$",multiline=True)

fun latexGetLine( src : vector<string>, lineNo : int ) : string
{
  if (lineNo <= 0 || lineNo > src.length) then "" else {
    catch( { src[lineNo - 1] }, fn(_) { "" })
  }
}
