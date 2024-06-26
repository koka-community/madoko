/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Parse math dimension file
module mathParse

import std/text/regex
import std/data/dict
import common
import options

// parse a dimension file written by latex snippets
pub fun parseMathDim( txt : string, opts : mathoptions  ) : (dict<mathinfo>,string,string) {
  val mi = mdict()
  val paths = mdict()
  var svgsize    : int := 0
  var svgreduced : int := 0
  val baseline  = opts.baseline.double / 100.0

  txt.findAll(rxDimLine).foreach fn(cap) {    
    val page      = cap.groups[2].parseInt.maybe(0,id)
    val ptwidth   = dimension(cap.groups[4],cap.groups[5])
    val ptheight  = dimension(cap.groups[6],cap.groups[7])
    val ptdepth   = dimension(cap.groups[8],cap.groups[9])
    val iwidth    = dimension(cap.groups[10],cap.groups[11]) 
    val iheight   = dimension(cap.groups[12],cap.groups[13])
    val bboxadj   = dimension(cap.groups[14],cap.groups[15])
    val size      = cap.groups[16].parseInt.maybe(0,id)
    val mime      = cap.groups[17]
    val imageData = cap.groups[18]
    val ext       = match (mime.find(rxMimePre)) {
                      Just(mcap) -> "." ++ mcap.groups[1]
                      Nothing    -> ".png"
                    }
    val imageName = opts.imgDir ++ "/math-" ++ cap.groups[3] ++ ext

    val height = if (iheight > 0.0) then iheight else ptheight
    val width  = if (iwidth > 0.0) then iwidth else ptwidth
    val depth  = if (ptheight != 0.0) then ptdepth * (height / ptheight) else 0.0

    val embed = if (!opts.svgShare || mime!="image/svg+xml") then imageData else {
      svgsize := svgsize ++ size
      var renames := []
      val svg = imageData.replaceAll(rxSvgPath, fn(pcap) {
        val pathid = pcap.groups[1]
        val ps     = paths[pathid].maybe([],id)
        val path   = pcap.matched
        val idx    = match(ps.findIdx(path)) {
                        Nothing -> {
                          //if (ps.isNil)  then trace("new path: " ++ pathid)
                          // else trace("new path with same id: " ++ pathid ++ " -" ++ ps.length.show)
                          paths[pathid] := ps ++ [path]
                          ps.length
                        }
                        Just(i) -> {
                          //trace("share path: " ++ pathid)
                          svgreduced := svgreduced ++ path.length
                          i
                        }
                      }
        if (idx > 0) then renames := Cons( (pathid, pathid ++ "-" ++ idx.show), renames )
        ""        
      })
      svg.renameIds(renames).replaceAll("<defs></defs>","")
    }

    val scale = opts.getMathScale(if (mime=="image/svg+xml") then Svg else Png).double / 100.0

    //trace("found: " ++ cap.groups[2] ++ ": " ++ cap.groups[3])
    mi[cap.groups[3]] := Mathinfo(imageName,page,scale*height,scale*width,(scale*depth) + baseline,
                                    iheight,iwidth,scale*bboxadj,size,embed,imageData)
  }

  val msg = if (svgreduced <= 0) then ""
             else " svg reduction:  " ++ (100.0 * svgreduced.double / svgsize.double).int.show.align(2) ++ "% to " ++ 
                      (svgsize - svgreduced).showSize ++ " (due to path sharing)"
  val svgpaths = paths.list.concat(renamePaths).join("\n")
  val svgdefs  = if (svgpaths.isEmpty) then "" else 
    "\n<svg id='math-svg-paths' style='display:none' version='1.1' viewBox='0 0 0 0' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'>\n" +
    "<defs>\n" ++ svgpaths ++ "\n</defs>\n</svg>\n"

  return (mi.freeze(), svgdefs, msg)
}   
val rxMimePre = regex(r"^image/(\w+)")
val rxSvgPath = regex(r"<path\b(?:[^/>]|/(?![^>]))*?\bid='([^']+)'(?:[^/>]|/(?![^>]))*?/>")

pub val rxDimLine = regex(r"^((\d+) *, *([a-zA-Z0-9]+) *" ++ 
                          rxDim ++ rxDim ++ rxDim ++ ")" +
                           "(?:" ++ rxDim ++ rxDim ++ rxDim ++ rxNum ++ rxMime ++ rxEmbed ++ ")?$", multiLine=True)
val rxDim = r", *(\d+)(?:\.(\d+))? *pt\b *"
val rxEmbed = r"(?:, *(data:.*))?"
val rxNum   = r", *(\d+) *"
val rxMime  = r", *(image/[\w\+]+) *"

pub fun dimension( whole : string, fraction : string ) : double {
  val w = whole.parseInt.maybe(0,id).double
  val f = (fraction ++ "00000").substr(0,5).parseInt.maybe(0,id).double / 100000.0
  return (w+f)
}

pub fun containsSnippet( txt : string ) : bool {
  txt.contains(rxDigest)
}

pub val rxDigest = regex(r"\\begin{md(?:Inline|Display)Snippet}[\[\{]([a-fA-F0-9]{32})[\}\]]")


// return all tex content outside snippets and line comments
pub fun unsnippet( txt : string, which : string ) : string {
  val res = txt.replaceAll( rxSnippet, "" ).replaceAll( rxComment, "" ).replaceAll(rxLines, "\n")
  //trace("**** unsnippet pre " ++ which ++ " ****\n" ++ txt ++ "\n*******")
  //trace("**** unsnippet " ++ which ++ " ****\n" ++ res.replaceAll("\n","-") ++ "\n*******")
  res
}

val rxSnippet = regex( r"\\begin{md(?:Inline|Display)Snippet}[\s\S]*?\\end{md(?:Inline|Display)Snippet}" )
val rxComment = regex( r"\r?\n[ \t]*%[^\r\n]*" )
val rxLines   = regex( r"(?:\r?\n)+")

pub fun showSize( size : int ) : string {
  val kb = 1024
  if (size < 10*kb) 
   then (size.double / kb.double).showFixed(1).align(4) ++ " kb"
   else ((size + kb - 1)/kb).show.align(4) ++ " kb"
}

fun findIdx( xs : list<string>, id : string, acc : int = 0 ) : maybe<int> {
  match(xs) {
    Nil -> Nothing
    Cons(x,xx) -> {
      if (x==id) then Just(acc) else findIdx(xx,id,acc+1)
    }
  }
}

fun renamePaths( pid: (string,list<string>) ) : list<string> {
  val pathid = pid.fst
  pid.snd.mapIndexed fn(idx,path) {
    if (idx==0) then path else {
      val newid = pathid ++ "-" ++ idx.show
      // trace("do path rename: " ++ pathid ++ " -> " ++ newid)
      path.renameIds( [(pathid,newid)])
    }
  }
}

fun renameIds( svg : string, renames : list<(string,string)> ) {
  // rename path id's
  val d = renames.dict
  svg.replaceAll(rxSvgId, fn(cap) {
    val id = cap.groups[2]
    match(d[id]) {
      Nothing     -> cap.matched
      Just(newid) -> {
        // trace("do local rename: " ++ id ++ " -> " ++ newid)      
        cap.groups[1] ++ newid
      }
    }
  })
}

val rxSvgId = regex(r#"\b(id=['"]|xlink:href=['"]#|url\()([\w\-]+)(?=['"\)])"#) // specific to dvisvgm