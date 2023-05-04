# WikiMedia dump file parser for Wiktionary, Wikipedia, and other projects.
#
# Copyright (c) 2018-2022 Tatu Ylonen.  See file LICENSE and https://ylonen.org

import html
import shutil
import subprocess

from typing import Optional
from collections.abc import Callable


def process_input(path: str, page_cb: Callable[[str, str], None], namespace_ids: set[int]) -> None:
    """Processes the entire input once, calling chunk_fn for each chunk.
    A chunk is a list of data, where ``data`` is a dict
    containing at least "title" and "text" keys.  This returns a list
    of the values returned by ``chunk_fn`` in arbitrary order.  Each return
    value must be json-serializable."""

    # Open the input file, optionally decompressing on the fly (in a parallel
    # process to maximize concurrency).  This requires the ``buffer`` program.
    from lxml import etree

    if path.endswith(".bz2"):
        bzcat_command = "lbzcat" if shutil.which("lbzcat") is not None else "bzcat"
        subp = subprocess.Popen([bzcat_command, path], stdout=subprocess.PIPE)
        wikt_f = subp.stdout
    else:
        wikt_f = open(path, "rb")

    namespace_str = "http://www.mediawiki.org/xml/export-0.10/"
    namespaces = {None: namespace_str}

    for _, page_element in etree.iterparse(wikt_f, tag=f"{{{namespace_str}}}page"):
        title = html.unescape(page_element.findtext("title", "", namespaces))
        title_without_prefix = title[title.find(":") + 1:]
        namespace_id = int(page_element.findtext("ns", "0", namespaces))
        if namespace_id not in namespace_ids or title_without_prefix.startswith("User:") or \
           title.endswith(("/documentation", "/testcases", "/sandbox")):
            page_element.clear(keep_tail=True)
            continue

        text = None
        redirect_to = None
        if (redirect_element := page_element.find("redirect", namespaces=namespaces)) is not None:
            redirect_to = html.unescape(redirect_element.get("title", ""))
        else:
            model = page_element.findtext("revision/model", "", namespaces)
            if model not in {"wikitext", "Scribunto", "json"}:
                # ignore css, javascript and sanitized-css pages
                page_element.clear(keep_tail=True)
                continue
            text = html.unescape(tpage_element.findtext("revision/text", "", namespaces))

        page_cb(title, namespace_id, body=text, redirect_to=redirect_to)
        page_element.clear(keep_tail=True)

    wikt_f.close()

def process_dump(ctx: Wtp, path: str, namespace_ids: set[int],
                 page_handler: Optional[Callable[[str, int], None]] = None) -> None:
    """Parses a WikiMedia dump file ``path`` (which should point to a
    "<project>-<date>-pages-articles.xml.bz2" file.  This implements
    the first phase of processing a dump - copying it to a temporary
    file with some preprocessing.  The Wtp.reprocess() must then be
    called to actually process the data."""

    # Run Phase 1 in a single thread; this mostly just extracts pages into
    # a temporary file.
    process_input(path, page_handler if page_handler else ctx.add_page, namespace_ids)

    # Analyze which templates should be expanded before parsing
    if not ctx.quiet:
        print("Analyzing which templates should be expanded before parsing", flush=True)
    ctx.analyze_templates()

# XXX parse <namespaces> and use that in both Python and Lua code

# XXX parse <case> to determine whether titles are case-sensitive
