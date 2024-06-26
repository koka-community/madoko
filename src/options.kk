/*---------------------------------------------------------------------------
  Copyright 2013 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// The ":options" type and parsing of the command line
module options


import std/os/env
import std/data/dict
import std/os/flags
import std/text/regex
import std/os/path
import common

// Metadata is just a string to string map.
pub alias metadata = list<(string,string)>


// Mathematics rendering mode.
pub type mathmode {
  Static  // latex generated images
  Dynamic // mathjax
}

// Bibliography styles
pub type bibstyle {
  Bst( styleName: string, locale: string )
  Csl( styleName: string, locale: string )
}

pub struct mathoptions (
  mode      : mathmode = Static,  // mode used to render math
  render    : maybe<mathrender> = Nothing, // math rendering method
  renderFull: maybe<mathrender> = Nothing, // math rendering method for math-needfull snippets

  mathjax   : string = "",        // mathjax scripts path (use "default" for default path)
  mjext     : string = "",        // semicolon separated list of mathjax extensions

  imgDir    : string = "math",    // directory for static math images
  scale     : int    = 0,         // math scaling in percentage
  scalePng  : int    = 108,       // default scaling for png
  scaleSvg  : int    = 105,       // default scaling for svg
  dpi       : int    = 300,       // math resolution
  baseline  : int    = 0,         // math baseline offset in percentage of 1pt
  embedLimit: int    = 512*1024,  // maximal embedded math image size
  docClass  : string = "[10pt]book",

  svgShare  : bool   = True,      // share paths in embedded svg images
  svgPrec   : int    = 3,         // decimal points used in svg rendering
  svgDefs   : string = "",        // used internally to share svg definitions
  svgFontFormat: string = "",     // embed fonts directly in svg, use 'none' or '' to use SVG paths
  svgBBoxExact : bool = False,    // use exact bounding box

  concurrency   : int  = 4,       // max concurrency for generating math renderings

  dvipng        : string = "dvipng",  // used to extract png images for math
  dvisvg        : string = "dvisvgm",  // used to extract svg for math
  latex         : string = "", // if non-empty, used for math, use "" for the default program
  latexFull     : string = "", // if non-empty, used for math with math-needfull. Use "" for default program
  dvips         : string = "dvips",   // used with ps2pdf when mathlatexFull is empty
  ps2pdf        : string = "ps2pdf",
  convert       : string = "convert", // used to extract png's from pdf for math that needs it
  dim           : dict<mathinfo> = dict()  // static math dimension information
)


// The options
pub struct options(
  version  : string = "",  // Initialized to the program version
  bench    : bool = False, // turn off more expensive features for benchmarking
  verbose  : int  = 0,      // be more verbose
  verboseMaxLine : int = 78, // format lines to be no longer than 78 characters
  pedantic : bool = False, // more pedantic list style mode
  sanitize : bool = False, // never output user defined html and attributes
  xmp      : bool = False, // only process markdown between xmp tags
  full     : maybe<bool> = Nothing, // generate a full html/latex file instead of a snippet
  tex      : bool = False,  // generate latex file too
  pdf      : bool = False,  // generate pdf file too
  texzip   : bool = False,  // generate tex zip for a submission
  rebuild  : bool = False,  // always rebuild bibtex, math etc.
  sandbox  : bool = False,  // run in a sandbox: only allow reading/writing from a subdirectory
  prelude  : string = "prelude", // standard prelude definitions

  title    : string = "",  // html title
  css      : string = "madoko.css",  // link to css style
  scripts  : string = "",  // link to javascript files
  scriptsx  : string = "",  // link to javascript files loaded at the end
  htmlHeader: string= "",  // literal html header
  cssHeader: string = "",  // literal css header
  jsHeader : string = "",  // inline javascript header
  htmlFooter: string= "",  // literal html footer
  jsFooter : string = "",  // inline javascript footer
  htmlMeta : string = "name=\"viewport\" content=\"initial-scale=1.0\"",  // html meta tags
  texHeader: string= "",   // literal tex header
  texHeaderx: string= "",  // literal tex header in non-math mode only
  texDocHeader: string= "",   // literal tex header after begin{document}
  texDocHeaderx: string= "",  // literal tex header after begin{document} in non-math mode only
  texFooter: string= "",   // literal tex footer
  texSectionNum: bool = False, // use tex section numbering

  bibStyle : bibstyle = Csl("madoko-numeric",""),  // bibliography style file (.bst or .csl)
  bib      : string = "",  // bibliography definition files (.bib)
  locale   : string = "en-US", // language

  packages : string = "",  // link to latex packages (.sty)
  packagesx: string = "",        // packages in non-math mode only
  docClass : string = "",        // latex document class (.cls)

  citestyle     : maybe<citestyle> = Nothing,
  citeAll       : bool = False,
  tocDepth      : int  = 3, // max. depth for inclusion in the table of contents
  headingDepth  : int  = 3, // default depth where headings are numbered
  headingBase   : int  = 2, // heading level for #
  sectionMax    : int  = 0, // maximal depth for adding sections (0 = disable)
  sectionBase   : int  = 1, // starting section level.
  starBold      : bool = False, // use * for bold?
  prettyAlign   : int  = 2, // default alignment spaces for .pretty mode
  logo          : bool = True, // generate a logo at the end of the document

  math          : mathoptions = Mathoptions(),

  highlight     : bool = True,
  hilitelang    : string = "",        // semi-colon separated list

  pdflatex      : string = "",        // defaults to 'xe' + latex cmd
  bibtex        : string = "bibtex",
  latex         : string = "latex",   // used to generate dvi for math
  processTimeout: int = 0,            // kill child process after <timeout>

  zip           : string = "zip",     // zip program

  metadata      : metadata = [],
  embedinfos    : dict<embedinfo> = dict(),   // embed data, used in a browser
  embedLimit    : int = 512*1024,             // limit for embedding data (javascript, css, etc.)
  lineNo        : int = 1,                  // emit line no's. Use 0 to suppress.
  lineNoWeb     : bool = False,             // emit line no info in html pages.
  copyStyles    : bool = True,              // copy standard style files
  lineMap       : lineMap = End,            // keep track of line numbers in include files
  extractStart  : string = r"^(?:\/\/|--|[#%]|[<]!--|\(\*) *BEGIN *: *(\w+) *(?:--[>]|\*\))?$",
  extractEnd    : string = r"^(?:\/\/|--|[#%]|[<]!--|\(\*) *END *(?:[:] *(\w+) *)?(?:--[>]|\*\))?$"
);

pub fun getPdfLatex( opts : options ) : string {
  if (opts.pdflatex.bool) then opts.pdflatex
   else combine(opts.latex.dirname,"xelatex")
}

pub fun getMathLatexFull( opts : options ) : string {
  if (opts.math.latexFull.bool) then opts.math.latexFull
   else opts.getMathLatex
}

pub fun getMathLatex( opts : options ) : string {
  if (opts.math.latex != "") then opts.math.latex
  // elif (mrender.isPng) then opts.latex // dvi route is much faster for png extraction
  else opts.latex // was: opts.getPdfLatex, but pdflatex/latex proves more reliable for svg extraction
}

pub fun getMathjax( opts : mathoptions ) : string {
  if (opts.mathjax != "default") then opts.mathjax
   else "https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
}

pub fun getMathRender( opts : mathoptions, kind : mathkind ) : mathrender {
  match(kind) {
    Plain -> opts.getMathRender
    Full  -> opts.getMathRenderFull
  }
}

pub fun getMathRender( opts : mathoptions ) : mathrender {
  match(opts.render) {
    Nothing -> Svg
    Just(m) -> m
  }
}

pub fun getMathRenderFull( opts : mathoptions ) : mathrender {
  match(opts.renderFull) {
    Nothing -> opts.getMathRender
    Just(m) -> m
  }
}

pub fun getMathScale( opts : mathoptions, mrender : mathrender ) : int {
  if (opts.scale==0) then match(mrender) {
    Png -> opts.scalePng
    Svg -> opts.scaleSvg
  }
  else opts.scale
}

pub struct commandOptions(
  showVersion : bool = False,
  convertTex  : bool = False,
  outputDir   : string = "out",
  installDir  : string = "",
  inputs      : list<string> = [],
  options     : options = Options()
);

fun creq( f : (commandOptions,string) -> commandOptions, help : string ) : optionArg<commandOptions>
{
  Req(f,help)
}

fun cflag( f : (commandOptions,bool) -> commandOptions ) : optionArg<commandOptions>
{
  Flag(f)
}

fun oflag( f : (options,bool) -> options ) : optionArg<commandOptions>
{
  Flag(fn(co:commandOptions,b:bool) { co(options = f(co.options,b)) })
}

fun oreq( f : (options,string) -> options, help : string ) : optionArg<commandOptions>
{
  Req(fn(co:commandOptions,v:string) { co(options = f(co.options,v)) },help)
}

fun setbench( o : options, b : bool ) {
  if (b) then {
    o(tocDepth=0,bench=True)
  }
  else {
    o(tocDepth=3,bench=False)
  }
}

val optionsDesc : list<option<commandOptions>>
  = [ Option( "",  ["version"], cflag(fn(co,v) { co(showVersion = v) }),   "Display version information" ),
      Option( "v", ["verbose"], oflag(fn(o,v) { o(verbose = if (v) then o.verbose + 1 else 0) }),     "Be more verbose"),
      Option( "",  ["odir"],    creq(fn(co,s) { co(outputDir=s) },"DIR"), "Write output files to the specified directory" ),
      Option( "",  ["xmp"],     oflag(fn(o,v) { o(xmp = v) }),       "Only process markdown between <xmp> tags"),
      Option( "",  ["tex"],     oflag(fn(o,v) { o(tex = v) }),       "Generate a LaTeX file too"),
      Option( "",  ["pdf"],     oflag(fn(o,v) { o(pdf = v, tex = if (v) then True else o.tex) }),  "Generate PDF using LaTeX"),
      Option( "",  ["texzip"],  oflag(fn(o,v) { o(texzip = v, tex = if (v) then True else o.tex, pdf = if (v) then True else o.pdf, lineNo = 0) }), "Generate TeX zip for submission"),
      Option( "",  ["png"],     oflag(fn(o,v) { o(math = (o.math)(render = Just(if (v) then Png else Svg))) }),  "Use PNG instead of SVG for math in HTML"),
      Option( "",  ["convert-tex"], cflag(fn(co,v) { co(convertTex=v) }), "Convert input from TeX to Markdown"),

      Option( "f", ["fragment"], oflag(fn(o,v) { o(full=Just(!v)) }), "Generate a fragment instead of a full document"),
      Option( "",  ["logo"],     oflag(fn(o,v) { o(logo=v) }),        "Generate a logo at the end of the document" ),
      Option( "",  ["sanitize"], oflag(fn(o,v) { o(sanitize = v) }), "Always escape or suppress user defined html"),
      Option( "" , ["sandbox"],  oflag(fn(o,v) { o(sandbox=v) }),    "Run in a sandbox for secure server execution"),
      Option( "",  ["pedantic"], oflag(fn(o,v) { o(pedantic = v) }), "Pedantic mode"),
      Option( "",  ["bench"],    oflag(setbench),                     "For benchmarking: turn off numbering, etc."),
      Option( "",  ["installdir"], creq(fn(co,s) { co(installDir=s) },"DIR"), "Set installation directory explicitly"),
      Option( "r", ["rebuild"],  oflag(fn(o,v) { o(rebuild=v) }),    "Force rebuild bibliography, math, etc."),
      Option( "",  ["prelude"],  oreq(fn(o,s) { o(prelude=s) }, "FILE"), "Include <FILE> at start of the document"),
      Option( "",  ["verbose-max"], oreq(fn(o,s) { o(verboseMaxLine=parseIntDefault(s,78)) }, "LEN"), "Maximum line length for messages" ),

      Option( "m", ["meta"],     oreq(setMeta, "key:val"), "Semi-colon separated list of metadata values")
    ]

fun setMeta( opts0 : options, value : string ) : options {
  val keyvals = value.split(";").list
  keyvals.foldl(opts0) fn(opts : options,keyval) {
    val i = keyval.indexOf(":")
    if (i > 0) then {
      val key = keyval.substr(0,i).trim
      val s   = keyval.substr(i+1).trim
      opts(metadata = opts.metadata ++ [(key,s)] )
    }
    else {
      warning("illegal --meta option: " ++ value)
      opts
    }
  }
}

// Parse the options from the command line given some extra arguments (default `""`).
pub fun parseOptions( version : string, extra : string = "") : io maybe<commandOptions>
{
  parseOptionList(version, env/arguments ++ extra.split(" ").list.filter(fn(s) { s != "" }))
}

pub fun parseOptionList( version : string, cmdargs  : list<string> ) : io maybe<commandOptions>
{
  // testOptions.usageInfo( header ).println
  val (options,args,errs) = parse( CommandOptions(options = Options(version=version)), optionsDesc, cmdargs )

  if (!(errs.isNil)) then {
    println( errs.join("\n") ++ "\n" ++ fullUsageInfo() )
    Nothing
  }
  elif (options.showVersion) then {
    println( "Madoko, version " ++ version ++ ".")
    Nothing
  }
  elif (args.isNil) then {
    fullUsageInfo().println
    Nothing
  }
  else {
    Just(options(inputs = args).check())
  }
}

fun fullUsageInfo() {
  val header = "usage:\n madoko [options] files\n\noptions:"
  optionsDesc.usageInfo(header) ++ "\n\nPrefix a flag with 'no-' to negate it. For example '--no-logo'."
}

// sanitize options
fun check( cmdOptions : commandOptions ) : io commandOptions
{
  cmdOptions(installDir=if (cmdOptions.installDir=="") then programPath().dirname else cmdOptions.installDir)
}


pub fun getDocName( opts : options ) : string {
  match(opts.metadata.find(fn(kv) { kv.fst == "docname" })) {
    Just(kv) -> kv.snd ++ ": "
    Nothing  -> ""
  }
}

fun cutoff( s : string, n : int ) : string {
  if (n<=1) return s
  s.lines.map(fn(line) {
    if (line.length >= n) then line.substr(0,n - 1) ++ "\n" ++ line.substr(n - 1) else line
  }).unlines
}

pub fun indent( opts : options, s : string, maxLine : int = 78 ) : string {
  s.cutoff(maxLine).lines.map(fn(line) { "  " ++ line }).unlines
}

pub fun print( opts :options, msg : string, level : int = 1  ) {
  if (opts.verbose >= level) then println(opts.indent(opts.getDocName ++ msg,opts.verboseMaxLine))
}

pub fun printErr( opts :options, msg : string, level : int = 0  ) {
  if (opts.verbose >= level) then println(opts.indent(msg,opts.verboseMaxLine))
}
