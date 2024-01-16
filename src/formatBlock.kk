/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.
 
  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Format _block_ elements and and their inline elements.
module formatBlock

import std/text/regex
import std/data/dict
import common
import attributes // mergeDefault
import block
import inline
import formatInline
import htmlFormatter
//import texFormatter


pub struct formatContext( 
  inlineContext : inlineContext,
  tocBlocks   : dict<list<block>>,
  footnoteBlock : block,
  headingBase: int,
  langPrefix : string,
  pedantic : bool,
  lineMap : lineMap,
  fmt : formatter = FmtHtml
)

pub fun initialFormatContext( icontext : inlineContext, lineMap: lineMap, 
                                      headingBase : int, pedantic : bool, fmt : formatter ) {
  FormatContext(icontext,dict(),Empty,headingBase,"language-",pedantic, lineMap, fmt)
}

fun fmtEnv( contxt : formatContext, env : string, txt : string, attrs : attrs = attrsNone ) : string {
  match(contxt.fmt) {
    FmtHtml | contxt.inlineContext.bench -> tagEnv(env, txt, attrs, contxt.inlineContext.sanitize) // inline for efficiency
    _ -> contxt.inlineContext.fmtEnv(env,txt,attrs)
  }
}

fun fmtCmd( contxt : formatContext, cmd : string, txt : string, attrs : attrs = attrsNone ) : string {
  match(contxt.fmt) {
    FmtHtml | contxt.inlineContext.bench -> tagEnv(cmd, txt, attrs, contxt.inlineContext.sanitize) // inline for efficiency
    _ -> (contxt.inlineContext.xfmtCmd)(contxt.inlineContext,cmd,txt,attrs)
  }
}

fun fmtText( contxt : formatContext, txt : string ) : string {
  match(contxt.fmt) {
    FmtHtml -> txt  // inline for efficiency
    _       -> (contxt.inlineContext.xfmtCmd)(contxt.inlineContext,"",txt,attrsNone)
  }
}

fun fmtTable( contxt : formatContext, head : list<row>, body : list<row>, colattrs : list<attrs>, attrs : attrs = attrsNone ) : string {
  (contxt.inlineContext.xfmtTable)(contxt.inlineContext,head,body,colattrs,attrs)
}

fun escapeMath( txt : string, fmt : formatter ) : string {
  match(fmt) {
    FmtHtml -> txt.htmlEscape
    FmtTex  -> txt 
  }
}

/* --------------------------------------
  Process inline text in the blocks 
---------------------------------------- */

// Format blocks into html and parse and format all inline elements 
pub fun formatBlocks( contxt : formatContext, blocks : list<block> ) : string
{
  unsafeNoDiv{ formatBlocksX(contxt,blocks) }
}

pub fun formatBlocksX( contxt : formatContext, blocks : list<block> ) : div string
{
  formatBlocksAcc(contxt,blocks,builder()) 
}

fun formatBlocksAcc( contxt : formatContext, blocks : list<block>, acc : builder<h> ) : <st<h>,div> string
{
  match(blocks) {
    Nil -> acc.build
    Cons(block,rest) -> {
      match(block) {
        // inside lists we do not parse paragraphs, but parse per line
        // (because adjacent nested lists otherwise become part of a paragraph)
        // Here we re-discover paragraphs by treating lines that are ended by
        // a blank line as a paragraph again.
        Line(txt,loose,attrs) -> {
          val (lines,rest2) = rest.span(isLine)
          val content = txt + lines.map(lineText).join
          match(rest2) {
            Cons(Blank(_),rest3) -> {
              formatBlocksAcc(contxt,rest3,acc.append(formatBlock(contxt,Para(content,attrs))))
            }
            _ -> {
              // This is to emulate fully pedantic list mode where we always
              // combine text lines as a paragraph in a loose list
              val newblock = if (loose) then Para(content,attrs) else Line(content,loose,attrs)
              formatBlocksAcc(contxt,rest2,acc.append(formatBlock(contxt,newblock)))
            }
          }
        }
        // For TeX output, an equation or list environment should be part of a paragraph
        // If a paragraph is followed by a `.para-block` we mark the paragraph as `.para-continue` 
        Para(text,attrs) | !(contxt.inlineContext.bench) -> {
          match(rest) {
            Cons(Div(_,attrsd),_) | attrsd.hasClass("para-block") -> {
              formatBlocksAcc(contxt,rest,acc.append(formatBlock(contxt,Para(text,attrs.addClass("para-continue")))))
            }
            //Cons(List,_) -> {
            //  formatBlocksAcc(context,rest,acc.append(formatBlock(context,Para(text,attrs.addClass("para-continue")))))
            //}
            _ -> {
              formatBlocksAcc(contxt,rest, acc.append(formatBlock(contxt,block)))
            } 
          }
        }

        // otherwise just proces the block element.
        _ -> formatBlocksAcc(contxt,rest, acc.append(formatBlock(contxt,block)))
      }
    }
  }
}

fun lineText( b :  block ) {
  match(b) {
    Line(txt) -> txt
    _         -> ""
  }
}

fun getLineInfo( attrs : attrs ) : string {
  match(attrs.hasKey("data-line")) {
    Just(info) -> {
      val lineno = parseLineInfo(info).snd
      if (lineno <= 0 || info.startsWith("0;")) then "" else "%mdk-data-line={" + info + "}\n" 
    }
    Nothing    -> ""    
  }
}

fun deriveFirstLineInfo( attrs : attrs ) : attrs {
  match(attrs.hasKey("data-line-first")) {
    Just(info) -> attrsNone.addKeyval("data-line-first",info)
    Nothing -> {
      match(attrs.hasKey("data-line")) {
        Just(info) -> attrsNone.addKeyval("data-line-first",info)
        Nothing -> attrsNone
      }
    }
  }
}

/* --------------------------------------
   Output a single block element 
---------------------------------------- */

pub fun formatBlock( contxt : formatContext, block : block ) : div string 
{
  match(block) {
    Para(txt,attrs) -> {
      val content = formatInline(contxt.inlineContext, txt, attrs)
      if (attrs.notag)
       then contxt.fmtEnv("div", content, attrs) // content
      elif (content.contains(rxblank)) then "" else 
       contxt.fmtEnv("p", content, attrs)      
       //"<p>" + formatInline(context.inlineContext,txt) + "</p>"
    }

    Line(txt,_loose,attrs) -> {
      formatInline(contxt.inlineContext, txt, attrs)
    }

    Blank -> {
      match(contxt.fmt) {
        FmtTex -> ""
        _      -> "\n"
      }
    }
    
    Code(txt,_,attrs) -> {  
      attrs.logDataLine 
      contxt.inlineContext.fmtCode( "pre", txt, attrs )
    }

    List(tagname,items,attrs) -> {
      contxt.fmtEnv(tagname, formatBlocksX(contxt,items), attrs)
    }
    
    Item(bs,attrs)  -> {
      contxt.fmtEnv("li",formatBlocksX(contxt,bs), attrs)    
    }
     
    Heading(d,txt,attrs) -> { 
      contxt.fmtCmd("h" + min(6,max(1, d + contxt.headingBase - 1)).show, formatInline(contxt.inlineContext,txt,attrs), 
                     attrs.addKeyval("data-heading-depth",d.show))
    }

    HLine(attrs) -> {
      match(contxt.fmt) {
        FmtHtml -> "\n<hr " + attrs.htmlFormat("hr",contxt.inlineContext.sanitize) + ">\n" 
        _ -> contxt.fmtCmd("hr", "", attrs)
      }
    }
    
    Source(txt,input,parentAttrs) -> {
      parentAttrs.logDataLine 
      match(input) {
        Pre       -> {
          contxt.inlineContext.fmtCode("pre",txt,parentAttrs.deriveFirstLineInfo)
        }
        Math      -> {
          //("\\[" + txt.trim.escapeMath(context.fmt) + "\\]")
          // context.logLineInfo(parentAttrs)
          contxt.inlineContext.fmtMath(True,txt,parentAttrs.deriveMathAttrs,getLineInfo(parentAttrs))
        }
        MathPre   -> {
          // ("\\[" + txt.mathPreBlock.escapeMath(context.fmt) + "\\]")
          // context.logLineInfo(parentAttrs)
          contxt.inlineContext.fmtMath(True,txt.mathPreBlock,parentAttrs.deriveMathAttrs,getLineInfo(parentAttrs))
        }
        MathDefs  -> {
          //context.logLineInfo(parentAttrs)
          val lineInfo = getLineInfo(parentAttrs)
          val mtxt = txt.escapeMath(contxt.fmt)
          match(contxt.fmt) {
            FmtTex  -> lineInfo + mtxt
            FmtHtml -> {
              log("math-full","%mdk-begin-mathdefs\n" + lineInfo + txt + "\n")
              if (contxt.inlineContext.mathStatic) then {
                log("math-plain","%mdk-begin-mathdefs\n" + lineInfo + txt + "\n")
                ""
              }
              else {
                "\\[" + mtxt + "\\]"
              }
            }
          }
        }
        Markdown  -> contxt.inlineContext.formatInline(txt,parentAttrs)
        Raw(monly)-> {
          if (contxt.inlineContext.sanitize) then ""
          else match(monly) {
            Nothing -> txt + "\n"
            Just(FmtTex) | contxt.fmt == FmtTex -> {
              val lineInfo = getLineInfo(parentAttrs)
              "%mdk-begin-texraw\n" + lineInfo + txt + "\n"
            }
            Just(f) | f == contxt.fmt -> txt + "\n"
            _       -> "\n" 
          }
        }
        // these should not happen by now
        Tex  -> contxt.inlineContext.fmtEscapePre(txt)
      }      
    }

    Quote(bs,attrs) -> {
      contxt.fmtEnv("blockquote", formatBlocksX(contxt,bs), attrs)
    }
    
    Table(header,colstyles0,cells,attrs) -> {
      val colstyles = colstyles0.map( fn(colstyle) { contxt.inlineContext.defaults.matchRules("tc",colstyle) } )
      val thead = formatRows(header,colstyles,contxt,attrs,False)
      val tbody = formatRows(cells,colstyles,contxt,attrs,True)
      contxt.fmtTable(thead,tbody, colstyles, attrs.addClass("madoko"))  
    }

    Div(Cons(Source(txt,Pre),Nil),attrs) | contxt.pedantic && attrs.elementName("div") == "pre" -> {
      contxt.formatBlock(Code(txt,""))
    }    

    Div(content,attrs) | attrs.hasClass("columns") -> {
      val cols = content.map fn(b) {
        match(b) {
          Div(bs,xs) -> {
            if (!(xs.hasClass("column"))) then {
              warning( "a 'Columns' block should only contain 'Column' blocks")
            }  
            Cell(contxt.formatBlocksX(bs), xs)
          }
          _ -> {
            warning( "a 'Columns' block can only contain 'Column' blocks")
            Cell(contxt.formatBlock(b), attrsNone)
          }
        }
      }
      contxt.fmtTable(Nil,[Row(cols)],cols.map(fn(c){ c.cellAttrs }),attrs)
    }    
    
    Div(content,attrs) -> {    
      val txt = formatBlocksX(contxt,content)
      val rnd = attrs.input
      match (attrs.hasKey("bib-id")) {
        Just(bibid) -> {
          log("aux","%mdk bib: " + bibid 
                + (attrs.hasKey("csl-style").maybe("",fn(s) { ", csl-style:" + s.show }))
                + (attrs.hasKey("bib-style").maybe("",fn(s) { ", bib-style:" + s.show }))
                + (attrs.hasKey("locale").maybe("",fn(s) { ", locale:" + s.show })) 
             )
        }
        Nothing     -> ()
      }
      if ((attrs.classes.isNil && attrs.keyvals.isNil && attrs.name=="") || attrs.notag || rnd.isRaw || 
            (contxt.fmt==FmtTex && rnd.isMathDefs))
        then txt 
        else contxt.fmtEnv("div",txt,attrs.addInputClass)
    }

    Special(name,value,attrs) -> {
      val linfo = contxt.inlineContext.fmtLineInfo(attrs.hasKey("data-line").mbstring)
      if (name.toLower=="toc") then {
        val blks = contxt.tocBlocks[value.toLower].maybe([],id)
        linfo + formatBlocksX(contxt,blks)
      }
      elif (name.toLower=="footnotes" && contxt.fmt.isFmtHtml) then linfo + formatBlock(contxt,contxt.footnoteBlock)
      else "" // formatBlock(context,Para("[" + name + "]\n"))
    }
    
    DefLink       -> ""
    DefFootnote   -> ""
    Empty         -> ""
  }
}
val rxblank = regex(r"^\s*$")
val rxDashes  = regex(r"^ *(\\/)?---+ *[|+]*$") //regex(r"^( |- |-- )*---+ *[- ]*[|+]*$")
val rxDDashes = regex(r"^ *(\\/)?===+ *[|+]*$")

fun deriveMathAttrs( parentAttrs : attrs ) {
  attrsNone.addClasses( parentAttrs.classes.filter(fn(c) { c.startsWith("snippet") || c.startsWith("math") } ) )
           .addKeyvals( parentAttrs.keyvals.filter( fn(kv) {
                          val key = kv.fst
                          key.startsWith("color") || key.startsWith("font-") || key.startsWith("snippet-") || key.startsWith("math-")
                        }))
}

fun formatRows( rows : list<row>, 
                      colstyles : list<attrs>, contxt : formatContext,
                      attrs : attrs, isBody : bool ) : list<row>
{
  if (rows.isNil) then return Nil

  fun defaultCellKeyvals( colNum : int, rowstyle : attrs, isLast : bool ) : list<(string,string)> {
    val mod  = if (colNum.even) then "even-" else "odd-"
    val elem = if (isBody) then "td-" else "th-"
    val idx  = colNum.show + "-"
    val prefixes = ["cell-","col-","col-" + mod, "col-" + idx,
                    elem, elem + mod, elem+idx] +
                   (if (isLast) then ["col-last-",elem + "last-"] else [])
    val allkvs  = attrs.keyvals + rowstyle.keyvals
    val kvs = allkvs.filterKeyvals(prefixes)
    kvs
  }

  fun formatRow( colNum : int, row : list<cell>, cols : list<attrs>, rowstyle : attrs ) : list<cell> {    
    match(row) {
      Cons(cell,rs) -> {
        match(cols) {
          Cons(colstyle,cs) -> {
            // merge with row style
            val colstyle0 = rowstyle.mergeDefault(colstyle)

            // span multiple columns?
            val (txt1,colspan) = match(cell.text.find(rxbars)) {
              Nothing   -> (cell.text,1)
              Just(cap) -> (cell.text.substr(0,cap.index), cap.matched.length)
            }
            // combine borders in case of a multi-column
            val (colstyle1,cs1) = if (colspan<=1) then (colstyle0,cs) 
                                    else {
                                      val colstylex = colstyle0.addKeyval("column-span",colspan.show)
                                      val colstyley = if (isBody) then colstylex 
                                                       else colstylex.addKeyval("text-align",rowstyle.hasKey("text-align").maybe("center",id))
                                      match(cs.drop(colspan - 2)) {
                                       Cons(colstylez,csx) 
                                           -> (colstyley.addClasses(colstylez.classes.filter(noalign))
                                                        .addKeyval("column-span",colspan.show), 
                                               csx )
                                       Nil -> (colstyley.addKeyval("column-span",colspan.show),Nil)
                                      }
                                    }
            // horizontal line?
            val (colstyle2,txt2,elemName) = if (txt1.contains(rxDashes))
                                    then (colstyle1.addClass("cell-line"), "","tl")
                                   elif (txt1.contains(rxDDashes))
                                    then (colstyle1.addClass("cell-double-line"), "","tl")
                                    else (colstyle1,txt1,if (isBody) then "td" else "th")
            
            val isLast = rs.isNil
            val extraClasses = [if (colNum.even) then "col-even" else "col-odd"] +
                                (if (isLast) then ["col-last"] else []) +
                                (if (colNum==1) then ["col-first"] else [])

            val colstyle3 = colstyle2.addClasses(extraClasses)
                                     .addKeyval("data-col",colNum.show)
            val colstyle4 = colstyle3.addKeyvals(defaultCellKeyvals(colNum,rowstyle,isLast))
            val colstyle5 = contxt.inlineContext.defaults.matchRules(elemName, colstyle4)
            val elem = Cell(contxt.inlineContext.formatInline(txt2,colstyle5), colstyle5)
            Cons(elem, formatRow( colNum+colspan, rs, cs1, rowstyle))        
          }
          _ -> Nil
        }
      }
      _ -> Nil  
    }
  }
  
  
  fun addRowKey( target : string, key : string, test : bool ) : list<(string,string)> {
    if (!test) then [] else {
      match(attrs.hasKey(key)) {
        Nothing -> []
        Just(value) -> [(target,value)]
      }
    }
  }

  fun filterKeyvals( keyvals : list<(string,string)>, prefixes : list<string> ) : list<(string,string)> {
    keyvals.filterMap fn(kv) {
      val (key,value) = kv
      match (prefixes.reverse.find(fn(pre) { key.startsWith(pre) })) {
        Just(pre) -> {
          val skey = key.substr(pre.length)
          if (skey.find(rxSubSelect).isJust) then Nothing else Just((skey,value))
        }
        Nothing -> Nothing
      }
    }
  }

  fun defaultKeyvals( hasLine :  bool, rowNum : int, isLast : bool ) : list<(string,string)> {
    val mod = if (rowNum.even && rowNum != 0) then "even-" else "odd-"
    val row = if (isBody) then "tbody-tr-" else "thead-tr-"
    val idx = rowNum.show + "-"
    val prefixes = ["tr-","tr-" + mod,"tr-" + idx,
                    row, row + mod, row + idx ] + 
                   (if (isLast) then ["tr-last-",row + "last-"] else [])
    val kvs = attrs.keyvals.filterKeyvals(prefixes)
    if (hasLine)
     then kvs.filter(fn(kv){kv.fst.startsWith("background-color") || kv.fst.startsWith("rule") })
     else kvs
  }

  fun containsDashes( row : row ) : bool {
    row.cells.any( fn(cell) { cell.text.contains(rxDashes) || cell.text.contains(rxDDashes) })
  }
         
  var rowNum := 0
  var rowCount := 0
  val firstHasLine = rows.take(1).all(containsDashes)
  val lastHasLine  = rows.reverse.take(1).all(containsDashes)
  val defaults = contxt.inlineContext.defaults
  rows.map fn(row) {
    rowCount := rowCount+1
    val hasLine = row.containsDashes
    val isLast  = !hasLine && (rowCount == rows.length - (if (lastHasLine) then 1 else 0)) 
    if (!hasLine) then rowNum := rowNum+1  

    val extraClasses = [if (isBody) then "tbody" else "thead",
                        if (rowNum.even) then "tr-even" else "tr-odd"] +
                       (if (isLast) then ["tr-last"] else []) +
                       (if (rowNum==1) then ["tr-first"] else [])
    val rowstyle0 = defaults.matchRules("tr", 
                      row.rowAttrs.addClasses(extraClasses).addKeyval("data-row",rowNum.show))
    val rowstyle = rowstyle0.addKeyvals( 
        addRowKey("rule-width", "rule-top-width", !isBody && rowNum==0 ) +
        addRowKey("rule-width", "rule-mid-width", isBody && rowNum==0 ) +
        addRowKey("rule-width", "rule-bottom-width", isBody && hasLine && rowCount == rows.length ) +
        addRowKey("rule-width", "rule-width", True ) +
        addRowKey("padding-top", "rule-top-sep", !isBody && firstHasLine && rowNum==1 && !hasLine ) +
        addRowKey("padding-top", "rule-mid-sep", isBody && rowNum==1 && !hasLine) +
        addRowKey("padding-bottom", "rule-mid-sep", !isBody && isLast ) +
        addRowKey("padding-bottom", "rule-bottom-sep", isBody && isLast ) 
      )
      .addKeyvals( defaultKeyvals(hasLine,rowNum,isLast) )
    Row(formatRow(1,row.cells,colstyles,rowstyle),rowstyle)
  }
}
val rxbars = regex(r"[|+]+$")
val rxSubSelect = regex(r"^(even|odd|last|\d+)\-")

fun noalign( s : string ) : bool
  !(s.startsWith("align-"))
