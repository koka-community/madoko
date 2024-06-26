/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Process the bilbliography
module bibliography

import std/text/regex
import std/os/path
import std/data/dict
import common
import options
import storage
import texParser
import includes
import runcsl



pub fun extractCitestyle( opts : options, outName : string ) : io options {
  val auxName  = outName.noext ++ "-bib.bbl.mdk" // the first..
  val contents = readTextFileDef( auxName, "", False )
  match (contents.find(rxCiteStyle)) {
    Nothing   -> opts
    Just(cap) -> {
      match(parseCiteStyle(cap.groups[1])) {
        Nothing  -> opts
        Just(cs) -> opts(citestyle=Just(cs),metadata=Cons(("cite-style",cap.groups[1]),opts.metadata))
      }
    }
  }
}
val rxCiteStyle = regex(r#"\bcite\-style *: *"([^"]+)""#)


// Generate CSL bibliography; return `True` if successful
fun genBibCsl( aux : auxinfo, outdir, searchDirs, mopts : options ) : io bool {
  mopts.print("bibliography " ++ (if (aux.auxid.bool) then "(" ++ aux.auxid ++ ") " else "") ++ "style: " ++ aux.style.styleName.stemname)
  val searchDirsCsl = searchDirs.concat( fn(dir) { [dir,combine(dir,"csl")] } )
  val searchDirsLoc = searchDirs.concat( fn(dir) { [dir,combine(dir,"locales")] } )

  val madokoStyle = searchReadTextFile( "madoko.csl", searchDirsCsl, "", True, mopts)
  val locale      = searchReadTextFile( "locales-" ++ aux.style.locale ++ ".xml",searchDirsLoc, "", True, mopts )
  val auxcontents = readTextFileDef(aux.auxfile,"",False)
  val bibfiles    = mopts.bib.splitPaths.map( fn(bib) { 
                      searchReadTextFile(bib, searchDirs,".bib",True,mopts) 
                    })
  val citations   = auxcontents.findCitations
  val cslStyle0   = searchReadTextFile( aux.style.styleName, searchDirsCsl, ".csl", True, mopts )
  val cslStyle    = match (cslStyle0.contents.find(rxIndepParent)) {
                      Nothing   -> cslStyle0
                      Just(cap) -> {
                        mopts.print("      parent style: " ++ cap.groups[1])
                        searchReadTextFile( cap.groups[1], searchDirsCsl, ".csl", True, mopts )
                      }
                    }

  if (citations.length > 0 && cslStyle.contents.bool && madokoStyle.contents.bool && locale.contents.bool) then {
    // ready to invoke CSL processor
    val res = runCsl( citations, bibfiles, cslStyle, madokoStyle, locale, aux.auxid , "")
    if (res.warnings.bool) then mopts.printErr(res.warnings);
    if (res.errors.bool) then {
      mopts.printErr(res.errors)
      False
    }
    else {    
      writeTextFileSync( aux.auxfile.changeExt(".bbl.mdk"), res.bibliography )
      writeTextFileSync( aux.auxfile.changeExt(".bib.json"), res.bib)   
      writeFinalAux( aux.auxfile ) 
    }
  }
  else {
    mopts.printErr("could not find all required CSL bibliography files")
    False
  }
}

val rxIndepParent = regex(r#"<link *href *= *"(?:https?://www.zotero.org/styles/)?([^"]+)" *rel *= *"independent-parent" */>"#)

fun searchReadTextFile( fname, searchDirs, ext, required, mopts ) : io fileinfo {
  match(trySearchReadTextFile(fname,searchDirs,ext,required)) {
    Nothing -> {
      mopts.printErr("warning: unable to read: " ++ fname.defaultExt(ext))
      Fileinfo(fname,"")
    }
    Just((fullname,contents)) -> Fileinfo(fullname,contents)
  }
}


fun findCitations( aux : string ) : list<citeinfo> {
  var lineinfo := ""
  aux.lines.list.map( fn(line) {
    match (line.find(rxDataLine)) {
      Just(cap) -> {
        lineinfo := cap.groups[1]
        Nothing
      }
      Nothing -> match(line.find(rxCitation)) {
        Just(cap) -> Just(Citeinfo(cap.groups[1], lineinfo ))
        Nothing   -> Nothing
      }
    }   
  }).concatMaybe
}
val rxCitation = regex(r"^\\citation\{([^\}]+)\}")
val rxDataLine = regex(r"^%mdk-data-line=\{([^\}]+)\}")

pub fun genBibtex( runBibtex, auxInfos : list<auxinfo>, outdir, searchDirs, mopts : options, continue : (bool) -> io () ) : io () {
  val (csls,bsts) = auxInfos.partition( fn(info) { info.style.isCsl } );

  fun continueCsl(biberr) {
    val ok = csls.all fn(aux) {
      genBibCsl( aux, outdir, searchDirs, mopts )
    }
    continue(biberr || !ok);
  }

  // copy .bst files to the output directory since Bibtex requires that
  bsts.foreach fn(aux) {
    val bstyle = aux.style.styleName
    if (bstyle.extname != "" || bstyle.dirname != "") then {
      // copy bst file
      tryCopyTextFileFromTo( bstyle.basename.defaultExt(".bst"), bstyle.dirname, outdir, True )
      ()
    }     
  }
  
  // run Bibtex first
  runBibtex(bsts.map(auxfile),mopts) fn(err:bool) {
    if (!err) then {
      val ok = bsts.all fn(bib) {
        val bblname = bib.auxfile.changeExt(".bbl")
        match (tryReadTextFile(bblname, True)) {
          Left -> {
            warning("Unable to read bibliography file: " ++ bblname)
            False
          }
          Right(bbl) -> {
            val bibl    = parseTex(bbl,bib.auxid,mopts.citestyle.maybe(citeNumeric,id),bib.style.styleName.stemname)
            val mdkname = bblname ++ ".mdk"
            writeTextFileSync(mdkname,bibl)  
            writeFinalAux(bib.auxfile)            
          }
        }
      }
      continueCsl(!ok);
    }
    else continueCsl(err);
  }
}

// Write the final aux file; returns `True` if successful
fun writeFinalAux( auxfile : string ) : io bool {
  tryCopyTextFile( auxfile, auxfile.changeExt(".final.aux"), True )
}

struct auxinfo(
  auxfile: string,
  auxid  : string,
  style  : bibstyle
)

pub fun writeCitationsData( citeData : string, outName : string, searchDirs : list<string>, bibNames : list<string>, opts : options ) : io list<auxinfo> {
  val defaultAux = outName.noext ++ "-bib.aux"
  val cites = splitCiteData( citeData, opts ) // split citations over multiple bibliographies
  val bibData = createBibData( outName.dirname, searchDirs, bibNames, opts.citestyle ) // copy bib files and compute md5's  
  cites.filterMap( fn(kv) {
    val (auxStem,(auxData,bibStyle)) = kv
    val auxName = outName.noext ++ "-bib"+ (if (auxStem=="") then "" else "-" ++ auxStem) ++ ".aux"
    val changed = writeCitations(auxData, bibData, bibStyle, auxName, opts)  // write aux files and compare to final.aux for changes
    //trace("bib: " ++ auxName ++ ", changed: " ++ changed.show ++ "\n" ++ auxData.indent(2))
    if (changed || opts.rebuild) then Just( Auxinfo(auxName,auxStem,bibStyle) ) else Nothing
  })
}

// split citations in different parts: one for each bibliography ([BIB=<id>] element)
fun splitCiteData( citeData : string, opts : options ) : io list<(string,(string,bibstyle))> {
  if (citeData.trim == "") return []
  val style = match (opts.bibStyle) {
                Csl(name,loc) | loc.isEmpty -> Csl(name,opts.locale)
                Bst(name,loc) | loc.isEmpty -> Bst(name,opts.locale)
                bs -> bs 
              }
  match(citeData.find(rxBibFile)) {
    Nothing   -> return [("",(citeData,style))]
    Just(cap) -> {
      val auxName = cap.groups[1]
      val auxRaw  = citeData.substr(0,cap.index) // allow backward citations too??
      val auxData = 
        if (auxName.isEmpty) then auxRaw 
         else auxRaw.replaceAll("\\citation{" ++ auxName ++ ":", "\\citation{")
      val stylex = if (cap.groups[2].bool) then Csl(cap.groups[2],cap.groups[4])
                   elif (cap.groups[3].bool) then Bst(cap.groups[3],cap.groups[4])
                   else style
      auxInsert( auxName, auxData, stylex, splitCiteData( citeData.substr1(cap.next), opts ))
    }
  }
}
val rxBibFile = regex(r"^ *%mdk bib: *([^\s,]*) *(?:, *csl-style: *([^\s,]*) *)?(?:, *bib-style: *([^\s,]*))?(?:, *locale: *([^\s,]* *))?$", multiline=True )

fun auxInsert( auxName : string, auxData : string, style : bibstyle, xs : list<(string,(string,bibstyle))> ) : list<(string,(string,bibstyle))> {
  match(xs) {
    Nil -> [(auxName,(auxData,style))]
    Cons(x,xx) -> {
      if (x.fst == auxName) 
       then Cons( (x.fst, (auxData ++ "\n" ++ x.snd.fst, style)), xx)
       else Cons( x, auxInsert(auxName,auxData,style, xx) )
    }
  }
}


// Find and copy bib files to the output directory, and return a `bibdata` command with md5 hash
fun createBibData( auxDir : string, searchDirs : list<string>, bibNames : list<string>, mcs : maybe<citestyle> ) : io string {
  val (bibStems,bibContents) = bibNames.map( fn(bibName) {
    match(trySearchReadTextFile(bibName,searchDirs,".bib")) {
      Nothing -> {
        warning( "unable to find bibliography file: " ++ bibName )
        []
      }
      Just((bibFile,content)) -> {
        // trace("bib: found: " ++ bibFile)
        if (dirname(bibFile) != auxDir) then {
          if (!(tryWriteTextFile( combine(auxDir,basename(bibFile)), content))) then {
            println("warning: unable to copy bibliography file to output directory: " ++ bibName)
          }
        }
        // "\\bibdata{" ++ stemname(bibFile) ++ "}\n%md5:" ++ md5(content) ++ "\n"
        [(stemname(bibFile),content)]
      }
    }
  }).concat.unzip
  val digest = bibContents.join.md5  
  "\\bibdata{" ++ bibStems.join(",") ++ "}\n%md5:" ++ digest ++ 
    (match(mcs) { Nothing -> ""; Just(cs) -> "\n%\\citestyle{" ++ cs.show ++ "}" }) ++ "\n"
}

// Write citations to an aux file. Returns "True" if the bibliography data changed.
fun writeCitations( auxData : string, bibData : string, bibStyle: bibstyle, auxName : string, opts : options ) : io (bool) {
  val oldData = readTextFileDef(auxName.changeExt(".final.aux"),"",False)
  val newData = "% Generated by Madoko, version " ++ opts.version ++ "\n" ++ auxData ++ "\n" +
                  (match(bibStyle) {
                    Bst(style,locale) -> "\\bibstyle{" ++ style.stemname ++ "}\n%\\biblocale{" ++ locale ++ "}\n"
                    Csl(style,locale) -> "%\\cslstyle{" ++ style ++ "}\n%\\csllocale{" ++ locale ++ "}\n"
                  }) 
                  ++ bibData
                  
  if (newData != oldData) then {
    if (!(tryWriteTextFile(auxName, newData))) then {
      opts.printErr("error: unable to write citations: " ++ auxName )
    }
  }
  
  val oldCites = oldData.findAll(rxCite).list.map(fn(cap) { cap.matched }).join("\n");
  val newCites = newData.findAll(rxCite).list.map(fn(cap) { cap.matched }).join("\n");
  //trace("oldCites: " ++ oldCites)
  //trace("newCites: " ++ newCites)
  return (oldCites != newCites)
}
val rxCite = regex(r#"^(?:(?:%?\\(citation|bibstyle|biblocale|bibdata|cslstyle|cslocale|citestyle)\b.*)|(?:%md5:.*))$"#,multiline=True)


