{
    var g = options.generator;
    g.setErrorFn(error);
}


preamble =
    // preamble starts with P macro, then only HV and P macros in preamble
    (skip_all_space escape &is_preamble macro)+
    (skip_all_space escape (&is_hvmode / &is_preamble) macro)*
    skip_all_space
    (escape begin skip_space begin_group "document" end_group / &{ error("expected \\begin{document}") })
        d:document
    escape end skip_space begin_group "document" end_group
    .*
    EOF
    { return d; }
    /
    // or, if no preamble was given, start default documentclass
    &{ g.macro("documentclass", [null, g.documentClass, null]); return true; }
    d:document
    EOF
    { return d; }


document =
    & { g.startBalanced(); g.enterGroup(); return true; }
    skip_all_space            // drop spaces at the beginning of the document
    pars:paragraph*
    skip_all_space            // drop spaces at the end of the document
    {
        g.exitGroup();
        g.isBalanced() || error("groups need to be balanced!");
        var l = g.endBalanced();
        // this error should be impossible, it's just to be safe
        l == 1 && g.isBalanced() || error("grammar error: " + l + " levels of balancing are remaining, or the last level is unbalanced!");

        g.createDocument(pars);
        g.logUndefinedRefs();
        return g;
    }



paragraph =
    vmode_macro
    / (escape noindent)? b:break                { b && g.break(); return undefined; }
    / skip_space n:(escape noindent)? txt:text+ { return g.create(g.par, txt, n ? "noindent" : ""); }
    // continue: after an environment, it is possible to contine without a new paragraph
    / e:environment                             { g.continue(); return e; }



// here, an empty line or \par is just a linebreak - needed in some macro arguments
paragraph_with_linebreak =
    text
    / vmode_macro
    / environment
    / break                                     { return g.create(g.linebreak); }


text "text" =
    p:(
        ligature
      / primitive
      / !break comment                          { return undefined; }
      // !break, because comment eats a nl and we don't remember that afterwards - space rule also eats a nl
    )+                                          { return g.createText(p.join("")); }

    / linebreak
    / hmode_macro
    / math

    // groups
    / begin_group                             & { g.enterGroup(); return true; }
      s:space?                                  { return g.createText(s); }
    / end_group                               & { if (!g.isBalanced()) { g.exitGroup(); return true; } } // end group only in unbalanced state
      s:space?                                  { return g.createText(s); }


// this rule must always return a string
primitive "primitive" =
      char
    / space                                     { return g.sp; }
    / hyphen
    / digit
    / punctuation
    / quotes
    / left_br
                                              // a right bracket is only allowed if we are in an open (unbalanced) group
    / b:right_br                              & { return !g.isBalanced() } { return b; }
    / nbsp
    / ctrl_space
    / diacritic
    / ctrl_sym
    / symbol
    / charsym
    / utf8_char



/**********/
/* macros */
/**********/


// macros that work in horizontal and vertical mode (those that basically don't produce text)
hv_macro =
    escape
    (
      &is_hvmode macro
      / logging
    )
    { return undefined; }


// macros that only work in horizontal mode (include \leavevmode)
hmode_macro =
    hv_macro
  /
    escape
    m:(
      &is_hmode m:macro { return m; }

    / noindent

    / smbskip_hmode / vspace_hmode
    / the

    / verb

    / &is_preamble only_preamble
    / !is_vmode unknown_macro       // now we have checked hv-macros and h-macros - if it's not a v-macro it is undefined
    )
    { return m; }


// macros that only work in vertical mode (include \par or check for \ifvmode)
vmode_macro =
    skip_all_space
    hv_macro
    { return undefined; }
  /
    skip_all_space
    escape
    m:(
      &is_vmode m:macro { return m; } / vspace_vmode / smbskip_vmode
    )
    skip_all_space
    { g.break(); return m; }



is_preamble =
    id:identifier &{ return g.isPreamble(id); }

is_vmode =
    id:identifier &{ return g.isVmode(id); }

is_hmode =
    id:identifier &{ return g.isHmode(id); }

is_hvmode =
    id:identifier &{ return g.isHVmode(id); }



macro =
    name:identifier skip_space &{ if (g.hasMacro(name)) { g.beginArgs(name); return true; } }
    macro_args
    {
        var args = g.parsedArgs();
        g.endArgs();
        return g.createFragment(g.macro(name, args));
    }



only_preamble =
    m:identifier
    { error("macro only allowed in preamble: " + m); }

unknown_macro =
    m:identifier
    { error("unknown macro: " + m); }



/************************/
/* macro argument rules */
/************************/


identifier "identifier" =
    $char+

key "key" =
    $(char / sp / digit / punctuation  / [$&_\-/@] / utf8_char)+



macro_args =
    (
        &{ return g.nextArg("X") }                                                                                              { g.preExecMacro(); }
      / &{ return g.nextArg("s") }    skip_space s:"*"?                                                                         { g.addParsedArg(!!s); }
      / &{ return g.nextArg("g") }    a:(arg_group      / . { error("macro " + name + " is missing a group argument") })        { g.addParsedArg(a); }
      / &{ return g.nextArg("gr") }   a:(restr_hgroup   / . { error("macro " + name + " is missing a group argument") })        { g.addParsedArg(a); }
      / &{ return g.nextArg("o") }    o: opt_group?                                                                             { g.addParsedArg(o); }
      / &{ return g.nextArg("i") }    i:(id_group       / . { error("macro " + name + " is missing an id group argument") })    { g.addParsedArg(i); }
      / &{ return g.nextArg("i?") }   i: id_optgroup?                                                                           { g.addParsedArg(i); }
      / &{ return g.nextArg("k") }    k:(key_group      / . { error("macro " + name + " is missing a key group argument") })    { g.addParsedArg(k); }
      / &{ return g.nextArg("n") }    n:(expr_group     / . { error("macro " + name + " is missing a num group argument") })    { g.addParsedArg(n); }
      / &{ return g.nextArg("l") }    l:(length_group   / . { error("macro " + name + " is missing a length group argument") }) { g.addParsedArg(l); }
      / &{ return g.nextArg("l?") }   l: length_optgroup?                                                                       { g.addParsedArg(l); }
      / &{ return g.nextArg("m") }    m:(macro_group    / . { error("macro " + name + " is missing a macro group argument") })  { g.addParsedArg(m); }
      / &{ return g.nextArg("u") }    u:(url_group      / . { error("macro " + name + " is missing a url group argument") })    { g.addParsedArg(u); }
      / &{ return g.nextArg("cl") }   c:(coord_group    / . { error("macro " + name + " is missing a coordinate/length group") })   { g.addParsedArg(c); }
      / &{ return g.nextArg("v") }    v:(vector         / . { error("macro " + name + " is missing a coordinate pair") })       { g.addParsedArg(v); }
      / &{ return g.nextArg("v?") }   v: vector?                                                                                { g.addParsedArg(v); }
    )*


// {identifier}
id_group        =   skip_space begin_group skip_space
                        id:identifier
                    skip_space end_group
                    { return id; }

// {\identifier}
macro_group     =   skip_space begin_group skip_space
                        escape id:identifier
                    skip_space end_group
                    { return id; }

// [identifier]
id_optgroup     =   skip_space begin_optgroup skip_space
                        id:identifier
                    skip_space end_optgroup
                    { return id; }

// {key}
key_group       =   skip_space begin_group
                        k:key
                    end_group
                    { return k; }

// lengths
length_unit     =   skip_space u:("sp" / "pt" / "px" / "dd" / "mm" / "pc" / "cc" / "cm" / "in" / "ex" / "em") _
                    { return u; }

  // TODO: should be able to use variables and maths: 2\parskip etc.
length          =   l:float u:length_unit (plus float length_unit)? (minus float length_unit)?
                    { return g.toPx({ value: l, unit: u }); }

// {length}
length_group    =   skip_space begin_group skip_space
                        l:length
                    end_group
                    { return l; }

// [length]
length_optgroup =   skip_space begin_optgroup skip_space
                        l:length
                    end_optgroup
                    { return l; }


// {num expression}
expr_group      =   skip_space begin_group
                        n:num_expr
                    end_group
                    { return n; }


// {float expression}
float_group     =   skip_space begin_group

                    end_group
                    { return f; }


// picture coordinates and vectors

// float or length
coordinate      =   skip_space c:(
                        length
                        /
                        f:float { return { value: f * g.length("unitlength").value,
                                            unit:     g.length("unitlength").unit };    }
                    ) skip_space
                    { return c; }

// (coord, coord)
vector          =   skip_space "(" x:coordinate "," y:coordinate ")" skip_space
                    { return { x: x, y: y }; }


// {coord}
coord_group     =   skip_space begin_group
                        c:coordinate
                    end_group
                    { return c; }



url_char        =   char/digit/punctuation/"-"/"#"/"&"/escape? "%" { return "%" }
                    / . &{ error("illegal char in url given"); }

// {url}
url_group       =   skip_space begin_group
                        url:(!end_group c:url_char {return c;})+
                    end_group
                    { return url.join(""); }



// {<LaTeX code/text>}
//
// group balancing: groups have to be balanced inside arguments, inside environments, and inside a document.
// startBalanced() is used to start a new level inside of which groups have to be balanced.
//
// In the document and in environments, the default state is unbalanced until end of document or environment.
// In an argument, the default state is balanced (so that we know when to take } as end of argument),
// so first enter the group, then start a new level of balancing.
arg_group       =   skip_space begin_group      & { g.enterGroup(); g.startBalanced(); return true; }
                        s:space?
                        p:paragraph_with_linebreak*
                    end_group
                    {
                        g.isBalanced() || error("groups inside an argument need to be balanced!");
                        g.endBalanced();
                        g.exitGroup();

                        s != undefined && p.unshift(g.createText(s));
                        return g.createFragment(p);
                    }


restr_hgroup    =   skip_space // restricted horizontal mode group


// [<LaTeX code/text>]
opt_group       =   skip_space begin_optgroup   & { g.enterGroup(); g.startBalanced(); return true; }
                        p:paragraph_with_linebreak*
                    end_optgroup                & { return g.isBalanced(); }
                    {
                        g.isBalanced() || error("groups inside an optional argument need to be balanced!");
                        g.endBalanced();
                        g.exitGroup();
                        return g.createFragment(p);
                    }



// calc expressions //


// \value{counter}
value           =   escape "value" c:id_group               { return c; }

// \real{<float>}
real            =   escape "real" skip_space
                    begin_group
                        skip_space f:float skip_space
                    end_group                               { return f; }



num_value       =   "(" expr:num_expr ")"                   { return expr; }
                  / integer
                  / real
                  / c:value                                 { return g.counter(c); }

num_factor      =   s:("+"/"-") skip_space n:num_factor     { return s == "-" ? -n : n; }
                  / num_value

num_term        =   head:num_factor tail:(skip_space ("*" / "/") skip_space num_factor)*
                {
                    var result = head, i;

                    for (i = 0; i < tail.length; i++) {
                        if (tail[i][1] === "*") { result = Math.trunc(result * tail[i][3]); }
                        if (tail[i][1] === "/") { result = Math.trunc(result / tail[i][3]); }
                    }

                    return Math.trunc(result);
                }

num_expr        =   skip_space
                        head:num_term tail:(skip_space ("+" / "-") skip_space num_term)*
                    skip_space
                {
                    var result = head, i;

                    for (i = 0; i < tail.length; i++) {
                        if (tail[i][1] === "+") { result += tail[i][3]; }
                        if (tail[i][1] === "-") { result -= tail[i][3]; }
                    }

                    return result;
                }



// **** macros the parser has to know about due to special parsing that is neccessary **** //


// spacing macros

// vertical
vspace_hmode    =   "vspace" "*"?   l:length_group      { return g.createVSpaceInline(l); }
vspace_vmode    =   "vspace" "*"?   l:length_group      { return g.createVSpace(l); }

smbskip_hmode   =   s:$("small"/"med"/"big")"skip"  _   { return g.createVSpaceSkipInline(s + "skip"); }
smbskip_vmode   =   s:$("small"/"med"/"big")"skip"  _   { return g.createVSpaceSkip(s + "skip"); }

//  \\[length] is defined in the linebreak rule further down




// verb - one-line verbatim text

verb            =   "verb" s:"*"? skip_space !char
                    b:.
                        v:$(!nl t:. !{ return b == t; })*
                    e:.
                    {
                        b == e || error("\\verb is missing its end delimiter: " + b);
                        if (s)
                            v = v.replace(/ /g, g.visp);

                        return g.create(g.verb, g.createVerbatim(v, true));
                    }




/****************/
/* environments */
/****************/

begin_env "\\begin" =
    skip_all_space
    escape begin                                { g.break(); }

end_env "\\end" =
    skip_all_space
    escape end
    begin_group id:identifier end_group         { return id; }

environment "environment" =
    begin_env begin_group                       & { g.startBalanced(); g.enterGroup(); return true; }
    e:(
        titlepage
      / abstract
      / itemize
      / enumerate
      / description
      / quote_quotation_verse
      / font
      / alignment
      / multicols
      / picture
      / unknown_environment
    )
    id:end_env
    {
        // each environment has to return a json object: { name: <name in begin>, node: <content node> }
        if (e.name != id)
            error("environment <b>" + e.name + "</b> is missing its end, found " + id + " instead");

        g.exitGroup();
        g.isBalanced() || error(e.name + ": groups need to be balanced in environments!");
        g.endBalanced();

        return e.node;
    }


unknown_environment =
    e:identifier
    { error("unknown environment: " + e); }


    

// titling

titlepage = name:"titlepage" end_group
    skip_space
    p:paragraph*
    {
        return {
            name: name,
            node: g.create(g[name], p)
        }
    }


abstract = name:"abstract" end_group        &{ g.setFontSize("small"); return true; }
    skip_space
    p:paragraph*
    {
        g.enterGroup();
        g.setFontWeight("bf");
        var head = g.create(g.list, g.macro("abstractname"), "center");
        g.exitGroup();

        g.startlist();
        var body = g.create(g.quotation, p);
        g.endlist();

        return {
            name: name,
            node: g.create(g[name], [head, body])
        }
    }


// lists: itemize, enumerate, description

itemize =
    name:"itemize" end_group
    &{
        g.startlist();
        g.stepCounter("@itemdepth");
        if (g.counter("@itemdepth") > 4) {
            error("too deeply nested");
        }
        return true;
    }
    items:(
        label:item &{ g.break(); return true; }             // break when starting an item
        pars:(!(item/end_env) p:paragraph { return p; })*   // collect paragraphs in pars
        { return [label, pars]; }
    )*
    {
        g.endlist();

        var label = "labelitem" + g.roman(g.counter("@itemdepth"));
        g.setCounter("@itemdepth", g.counter("@itemdepth") - 1);

        return {
            name: name,
            node: g.create(g.unorderedList,
                        items.map(function(label_text) {
                            // null means no opt_group was given (\item ...), undefined is an empty one (\item[] ...)
                            label_text[1].unshift(g.create(g.itemlabel, g.create(g.inlineBlock, label_text[0] !== null ? label_text[0] : g.macro(label))));

                            return g.create(g.listitem, label_text[1]);
                        }))
        }
    }


enumerate =
    name:"enumerate" end_group
    &{
        g.startlist();
        g.stepCounter("@enumdepth");
        if (g.counter("@enumdepth") > 4) {
            error("too deeply nested");
        }

        var itemCounter = "enum" + g.roman(g.counter("@enumdepth"));
        g.setCounter(itemCounter, 0);
        return true;
    }
    items:(
        label:(label:item {
            g.break();                                      // break when starting an item
            // null is no opt_group (\item ...)
            // undefined is an empty one (\item[] ...)
            if (label === null) {
                var itemCounter = "enum" + g.roman(g.counter("@enumdepth"));
                var itemId = "item-" + g.nextId();
                g.stepCounter(itemCounter);
                g.refCounter(itemCounter, itemId);
                return {
                    id:   itemId,
                    node: g.macro("label" + itemCounter)
                };
            }
            return {
                id: undefined,
                node: label
            };
        })
        pars:(!(item/end_env) p:paragraph { return p; })*   // collect paragraphs in pars
        {
            return {
                label: label,
                text: pars
            };
        }
    )*
    {
        g.endlist();
        g.setCounter("@enumdepth", g.counter("@enumdepth") - 1);

        return {
            name: name,
            node: g.create(g.orderedList,
                        items.map(function(item) {
                            var label = g.create(g.inlineBlock, item.label.node);
                            if (item.label.id)
                                label.id = item.label.id;
                            item.text.unshift(g.create(g.itemlabel, label));
                            return g.create(g.listitem, item.text);
                        }))
        }
    }


description =
    name:"description" end_group    &{ return g.startlist(); }
    items:(
        label:item &{ g.break(); return true; }             // break when starting an item
        pars:(!(item/end_env) p:paragraph { return p; })*   // collect paragraphs in pars
        { return [label, pars]; }
    )*
    {
        g.endlist();

        return {
            name: name,
            node: g.create(g.descriptionList,
                        items.map(function(label_text) {
                            var dt = g.create(g.term, label_text[0]);
                            var dd = g.create(g.description, label_text[1]);
                            return g.createFragment([dt, dd]);
                        }))
        }
    }



item =
    skip_all_space escape "item" !char og:opt_group? skip_all_space
    { return og; }


// quote, quotation, verse
quote_quotation_verse =
    name:("quote"/"quotation"/"verse") end_group    &{ return g.startlist(); }
    skip_space
    p:paragraph*
    {
        g.endlist();
        return {
            name: name,
            node: g.create(g[name], p)
        }
    }


// font environments

font =
    name:$
    ( size:  ("tiny"/"scriptsize"/"footnotesize"/"small"/
              "normalsize"/"large"/"Large"/"LARGE"/"huge"/"Huge")   &{ g.setFontSize(size); return true; }
    / family:("rm"/"sf"/"tt")"family"                               &{ g.setFontFamily(family); return true; }
    / weight:("md"/"bf")"series"                                    &{ g.setFontWeight(weight); return true; }
    / shape: ("up"/"it"/"sl"/"sc")"shape"                           &{ g.setFontShape(shape); return true; }
    / "normalfont"                                                  &{ g.setFontFamily("rm");
                                                                       g.setFontWeight("md");
                                                                       g.setFontShape("up"); return true; }
    ) end_group skip_space
    p:paragraph*
    {
        return {
            name: name,
            node: g.create(g.block, p)
        }
    }



// alignment:  flushleft, flushright, center

alignment =
    align:("flushleft"/"flushright"/"center")
    end_group
    skip_space
        p:paragraph*
    {
        // only set alignment on the g.list
        return {
            name: align,
            node: g.create(g.list, p, align)
        }
    }


// multicolumns

// \begin{multicols}{number}[pretext][premulticols size]
multicols =
    name:("multicols") end_group
    conf:(begin_group c:digit end_group o:opt_group? opt_group? { return { cols: c, pre: o } }
         / &{ error("multicols error, required syntax: \\begin{multicols}{number}[pretext][premulticols size]") }
         )
    pars:paragraph*
    {
        var node = g.create(g.multicols(conf.cols), pars)
        return {
            name: name,
            node: g.createFragment([conf.pre, node])
        }
    }



// graphics

// \begin{picture}(width,height)(xoffset,yoffset)
picture =
    name:("picture") end_group
    conf:(size:vector offset:vector? { return { size: size, offset: offset } }
         / &{ error("picture error, required syntax: \\begin{picture}(width,height)[(xoffset,yoffset)]") }
         )
    // TODO: rule for picture content??? LaTeX allows anything, Lamport says: HV macros and picture commands
    content:text*
    {
        var picture = g.createPicture(conf.size, conf.offset, content);

        return {
            name: name,
            node: picture
        }
    }





// comment

comment_env "comment environment" =
    "\\begin" skip_space "{comment}"
        (!end_comment .)*
    end_comment skip_space
    { g.break(); return undefined; }

end_comment = "\\end" skip_space "{comment}"




/**********/
/*  math  */
/**********/


math =
    inline_math / display_math

inline_math =
    math_shift            m:$math_primitive+ math_shift            { return g.parseMath(m, false); }
    / escape "("          m:$math_primitive+ escape ")"            { return g.parseMath(m, false); }

display_math =
    math_shift math_shift m:$math_primitive+ math_shift math_shift { return g.parseMath(m, true); }
    / escape left_br      m:$math_primitive+ escape right_br       { return g.parseMath(m, true); }


math_primitive =
    primitive
    / alignment_tab
    / superscript
    / subscript
    / escape identifier
    / begin_group skip_space end_group
    / begin_group math_primitive+ end_group
    / sp / nl / linebreak / comment


// shortcut for end of token
_                           = !char skip_space

/* kind of keywords */

begin                       = "begin"   _   {}
end                         = "end"     _   {}

par                         = "par" !char   {}
noindent                    = "noindent"_   {}

plus                        = "plus"    _   {}
minus                       = "minus"   _   {}

endinput                    = "endinput"_   .*


/* syntax tokens - TeX's first catcodes that generate no output */

escape                      = "\\"                              { return undefined; }       // catcode 0
begin_group                 = "{"                               { return undefined; }       // catcode 1
end_group                   = "}"                               { return undefined; }       // catcode 2
math_shift      "math"      = "$"                               { return undefined; }       // catcode 3
alignment_tab               = "&"                               { return undefined; }       // catcode 4

macro_parameter "parameter" = "#"                               { return undefined; }       // catcode 6
superscript                 = "^"                               { return undefined; }       // catcode 7
subscript                   = "_"                               { return undefined; }       // catcode 8
ignore                      = "\0"                              { return undefined; }       // catcode 9

EOF             "EOF"       = !. / escape endinput




/* space handling */

nl              "newline"   = !'\r''\n' / '\r' / '\r\n'         { return undefined; }       // catcode 5 (linux, os x, windows)
sp              "whitespace"= [ \t]                             { return undefined; }       // catcode 10

comment         "comment"   = "%"  (!nl .)* (nl sp* / EOF)                                  // catcode 14, including the newline
                            / comment_env                       { return undefined; }       //             and the comment environment

skip_space      "spaces"    = (!break (nl / sp / comment))*     { return undefined; }
skip_all_space  "spaces"    = (nl / sp / comment)*              { return undefined; }

space           "spaces"    = !break
                              !linebreak
                              !(skip_all_space escape is_vmode)
                              (sp / nl)+                        { return g.brsp; }

ctrl_space  "control space" = escape (&nl &break / nl / sp)     { return g.brsp; }          // latex.ltx, line 540

nbsp        "non-brk space" = "~"                               { return g.nbsp; }          // catcode 13 (active)

break     "paragraph break" = (skip_all_space escape par skip_all_space)+   // a paragraph break is either \par embedded in spaces,
                              /                                             // or
                              sp*
                              (nl comment* / comment+)                      // a paragraph break is a newline...
                              ((sp* nl)+ / EOF)                             // ...followed by one or more newlines, mixed with spaces,...
                              (sp / nl / comment)*                          // ...and optionally followed by any whitespace and/or comment

linebreak       "linebreak" = skip_space escape "\\" skip_space '*'?
                              skip_space
                              l:(begin_optgroup skip_space
                                    l:length
                                end_optgroup skip_space {return l;})?
                              {
                                  if (l) return g.createBreakSpace(l);
                                  else   return g.create(g.linebreak);
                              }


/* syntax tokens - LaTeX */

// Note that these are in reality also just text! I'm just using a separate rule to make it look like syntax, but
// brackets do not need to be balanced.

begin_optgroup              = "["                               { return undefined; }
end_optgroup                = "]"                               { return undefined; }


/* text tokens - symbols that generate output */

char        "letter"        = c:[a-z]i                          { return g.character(c); }  // catcode 11
digit       "digit"         = n:[0-9]                           { return g.character(n); }  // catcode 12 (other)
punctuation "punctuation"   = p:[.,;:\*/()!?=+<>]               { return g.character(p); }  // catcode 12
quotes      "quotes"        = q:[`']                            { return g.textquote(q); }  // catcode 12
left_br     "left bracket"  = b:"["                             { return g.character(b); }  // catcode 12
right_br    "right bracket" = b:"]"                             { return g.character(b); }  // catcode 12

utf8_char   "utf8 char"     = !(sp / nl / escape / begin_group / end_group / math_shift / alignment_tab / macro_parameter /
                                superscript / subscript / ignore / comment / begin_optgroup / end_optgroup /* primitive */)
                               u:.                              { return g.character(u); }  // catcode 12 (other)

hyphen      "hyphen"        = "-"                               { return g.hyphen(); }

ligature    "ligature"      = l:("ffi" / "ffl" / "ff" / "fi" / "fl" / "---" / "--"
                                / "``" / "''" / "!´" / "?´" / "<<" / ">>")
                                                                { return g.ligature(l); }

ctrl_sym    "control symbol"= escape c:[$%#&{}_\-,/@]           { return g.controlSymbol(c); }


// returns a unicode char/string
symbol      "symbol macro"  = escape name:identifier &{ return g.hasSymbol(name); } skip_space
    {
        return g.symbol(name);
    }


diacritic "diacritic macro" =
    escape
    d:$(char !char / !char .)  &{ return g.hasDiacritic(d); }
    skip_space
    c:(begin_group c:primitive? end_group s:space? { return g.diacritic(d, c) + (s ? s:""); }
      /            c:primitive                     { return g.diacritic(d, c); })
    {
        return c;
    }



/* TeX language */

// \symbol{}= \char
// \char98  = decimal 98
// \char'77 = octal 77
// \char"FF = hex FF
// ^^FF     = hex FF
// ^^^^FFFF = hex FFFF
// ^^c      = if charcode(c) < 64 then fromCharCode(c+64) else fromCharCode(c-64)
charsym     = escape "symbol"
              begin_group
                skip_space i:integer skip_space
              end_group                                         { return String.fromCharCode(i); }
            / escape "char" i:integer                           { return String.fromCharCode(i); }
            / "^^^^" i:hex16                                    { return String.fromCharCode(i); }
            / "^^"   i:hex8                                     { return String.fromCharCode(i); }
            / "^^"   c:.                                        { c = c.charCodeAt(0);
                                                                  return String.fromCharCode(c < 64 ? c + 64 : c - 64); }


integer     =     i:int                                         { return parseInt(i, 10); }
            / "'" o:oct                                         { return parseInt(o, 8); }
            / '"' h:(hex16/hex8)                                { return h; }


hex8  "8bit hex value"  = h:$(hex hex)                          { return parseInt(h, 16); }
hex16 "16bit hex value" = h:$(hex hex hex hex)                  { return parseInt(h, 16); }

int   "integer value"   = $[0-9]+
oct   "octal value"     = $[0-7]+
hex   "hex digit"       = [a-f0-9]i

float "float value"     = f:$(
                            [+\-]? (int ('.' int?)? / '.' int)
                          )                                     { return parseFloat(f); }


// distinguish length/counter: if it's not a counter, it is a length
the                     = "the" _ t:(
                            c:value &{ return g.hasCounter(c);} { return g.createText("" + g.counter(c)); }
                            / escape id:identifier skip_space   { return g.theLength(id); }
                        )                                       { return t; }

// logging
logging                 = "showthe" _ (
                            c:value &{ return g.hasCounter(c);} { console.log(g.counter(c)); }
                            / escape l:identifier skip_space    { console.log(g.length(l)); }
                        )
                        / "message" m:arg_group                  { console.log(m.textContent); }
