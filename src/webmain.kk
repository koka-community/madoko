/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Main Madoko client-side entry
module webmain

import std/data/dict
import version
import common
import options
import driver
import storage
import mathStatic

pub fun initialOptions( args : string = "" ) : io options {
  val opts = if (args=="") then Options(version=version/version)
              else match(parseOptions(version/version,args)) {
                Just(cmdOpts) -> cmdOpts.options
                Nothing       -> Options(version=version/version)
              }
  opts(lineNoWeb=True,
       math=(opts.math)(embedLimit=512*1024),   // must match server setting!
       embedLimit=0,
       copyStyles=False,
       verboseMaxLine=0)  
}

val coptions = CommandOptions()

pub fun writeTextFile( fileName : string, content : string ) : io () {
  storage/writeTextFileSync( fileName, content )
}

pub fun readTextFile( fname : string ) : io string {
  readTextFileSync( fname );
}

pub fun unlinkFile( fname : string ) : io () {
  unlinkSync(fname)
}

pub fun clearStorage() : io () {
  clear();
}

pub fun addImage( embeds : dict<embedinfo>, imageName : string, data : string ) : dict<embedinfo> {
  embeds + dict([(imageName,Embedinfo(imageName,data))])
}


pub fun markdown( inputName : string, input : string, outdir : string, options0 : options, modes: string, convertTex : bool,
                          continue: (md:string,stdout:string,needRerun:bool,options:options,
                                      files:string,filesRefer:string,filesWrite:string,labels:string,links:string,customs:string,entities:string) -> io () ) : io () 
{ 
  printRedirect( fn(s) {
    log("stdout",s)
  });

  val extramdata = modes.split(";").list.map( fn(key) { (key,"True") })
  val options    = options0( metadata = options0.metadata + extramdata )

  val copts = coptions(options = options, outputDir = outdir, convertTex = convertTex)
  val outName = outputName(inputName,copts)
  
  var rerun := False;

  fun runPdfLatex( srcFile : string, texFile : string, opts : options, content : string, cont : (int) -> io () ) : io () 
  {
    options.printErr("cannot generate pdf in the browser")
    cont(1)
  }

  fun runZip( files : list<string>, zipFile : string, opts : options, cont : (bool) -> io () ) : io () {
    options.printErr("cannot zip files in the browser")
    cont(False)
  }

  fun runBibtex( bibFiles : list<string>, opts : options, cont : bool -> io () ) : io () 
  {
    rerun := bibFiles.isCons
    //trace("bibtex rerun")
    cont(bibFiles.isCons)
  } 

  fun runMathStatic( content : string, inpName : string, outputname : string,
                          texNamePlain : string, texNameFull : string,
                          plainPages : pages, fullPages : pages,
                          oldMathPlain : string, oldMathFull : string,
                          xopts : options, cont : (maybe<(dict<mathinfo>,string)>) -> io () ) : io ()
  {
    rerun := True
    trace("math rerun")
    cont(Nothing)
  }

  val runners = Runners(runPdfLatex, runBibtex, runMathStatic, runZip )

  withLog("stdout") {
    withLog("files") {
      withLog("filesRefer") {
        withLog("filesWrite") {
          withLog("labels") {
            withLog("links") {
            withLog("customs") {
            withLog("entities") {
                processContent(inputName, outName, input, copts, True, runners, fn(output,_,_,options1) {
                  val stdout = getLog("stdout")
                  val files  = getLog("files")
                  val filesRefer  = getLog("filesRefer")
                  val filesWrite  = getLog("filesWrite")
                  val labels = getLog("labels")
                  val links = getLog("links")
                  val customs = getLog("customs")
                  val entities = getLog("entities")
                  continue(output,stdout,rerun,options1,files,filesRefer,filesWrite,labels,links,customs,entities)
                })
            }}}
          }
        }
      }
    }
  }
  ()
}
