import os
import re
import unicodedata
from collections import deque
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, unquote, urldefrag, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen


BASE_HOST = "corvinus-materials.azurewebsites.net"
ROOT_URL = f"https://{BASE_HOST}/python_psz/"
OUTPUT_ROOT = Path(__file__).resolve().parent / "BurkaDavidCourse_FM_HU"
INDEX_ONLY = os.environ.get("PYTHON_FM_INDEX_ONLY", "").lower() in {
    "1", "true", "yes", "on"
}
ALLOWED_HTML_PREFIXES = (
    "/python_psz/",
    "/python_basic/",
    "/python_advanced/",
)
ASSET_EXTENSIONS = {
    ".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp",
    ".ico", ".pdf", ".csv", ".ipynb", ".txt", ".woff", ".woff2",
    ".ttf", ".eot", ".json", ".map",
}


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attrs_by_name = dict(attrs)
        for attr_name in ("href", "src"):
            value = attrs_by_name.get(attr_name)
            if value:
                self.links.append(value)


def normalize(url):
    clean_url, _ = urldefrag(url)
    return clean_url


def request_url_for(url):
    parsed = urlparse(url)
    encoded_path = quote(parsed.path, safe="/%")
    return urlunparse(parsed._replace(path=encoded_path))


def sanitize_segment(segment):
    ascii_segment = unicodedata.normalize("NFKD", segment).encode(
        "ascii", "ignore"
    ).decode("ascii")
    ascii_segment = re.sub(r"\s+", "_", ascii_segment)
    ascii_segment = re.sub(r"[^A-Za-z0-9._-]", "_", ascii_segment)
    ascii_segment = re.sub(r"_+", "_", ascii_segment).strip("._")
    return ascii_segment or "index"


def sanitize_path(path):
    parts = [
        sanitize_segment(part)
        for part in Path(path).parts
        if part not in ("/", "")
    ]
    return Path(*parts) if parts else Path("index.html")


def local_path_for(url):
    parsed = urlparse(url)
    path = unquote(parsed.path or "/")
    if path.endswith("/"):
        path += "index.html"
    if "." not in Path(path).name:
        path = path.rstrip("/") + "/index.html"
    sanitized_path = sanitize_path(path)
    if parsed.netloc and parsed.netloc != BASE_HOST:
        return OUTPUT_ROOT / "_external" / sanitize_segment(parsed.netloc) / sanitized_path
    return OUTPUT_ROOT / sanitized_path


def should_queue_html(url):
    parsed = urlparse(url)
    return (
        parsed.scheme in ("http", "https")
        and parsed.netloc == BASE_HOST
        and parsed.path.startswith(ALLOWED_HTML_PREFIXES)
    )


def should_download_asset(url):
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return False
    extension = Path(parsed.path).suffix.lower()
    if parsed.netloc == BASE_HOST:
        return extension in ASSET_EXTENSIONS or parsed.path.startswith(ALLOWED_HTML_PREFIXES)
    return extension in ASSET_EXTENSIONS


def rewrite_html_links(text, page_url, target_path):
    def replace_link(match):
        original = match.group("url")
        if original.startswith(("mailto:", "javascript:", "data:", "#", "xhttps://")):
            return match.group(0)
        absolute = normalize(urljoin(page_url, original))
        if not (should_queue_html(absolute) or should_download_asset(absolute)):
            return match.group(0)
        relative = os.path.relpath(
            local_path_for(absolute), start=target_path.parent
        ).replace(os.sep, "/")
        return f"{match.group('prefix')}{relative}{match.group('suffix')}"

    return re.sub(
        r'(?P<prefix>\b(?:href|src)\s*=\s*["\'])(?P<url>[^"\']+)(?P<suffix>["\'])',
        replace_link,
        text,
        flags=re.IGNORECASE,
    )


def crawl():
    visited = set()
    downloaded = []
    errors = []
    queue = deque([ROOT_URL])

    while queue:
        url = normalize(queue.popleft())
        if url in visited:
            continue
        visited.add(url)

        try:
            request = Request(request_url_for(url), headers={"User-Agent": "Mozilla/5.0"})
            with urlopen(request, timeout=30) as response:
                content_type = response.headers.get_content_type()
                payload = response.read()
        except Exception as exc:
            errors.append((url, str(exc)))
            continue

        target_path = local_path_for(url)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_bytes(payload)
        downloaded.append(str(target_path.relative_to(OUTPUT_ROOT)))

        is_html = content_type == "text/html" or target_path.suffix.lower() in ("", ".html")
        if not is_html:
            continue

        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            text = payload.decode("latin-1", errors="ignore")

        rewritten_text = rewrite_html_links(text, url, target_path)
        if rewritten_text != text:
            target_path.write_text(rewritten_text, encoding="utf-8")

        parser = LinkParser()
        parser.feed(text)
        for raw_link in parser.links:
            if raw_link.startswith(("mailto:", "javascript:", "data:", "#", "xhttps://")):
                continue
            absolute = normalize(urljoin(url, raw_link))
            if should_queue_html(absolute):
                queue.append(absolute)
            elif should_download_asset(absolute) and absolute not in visited:
                queue.append(absolute)

    return downloaded, errors


def remove_rows_from_reduced_index():
    index_path = OUTPUT_ROOT / "python_psz" / "index.html"
    if not index_path.exists():
        return

    text = index_path.read_text(encoding="utf-8")
    row_pattern = re.compile(r"\s*<tr>.*?</tr>", re.DOTALL | re.IGNORECASE)
    excluded_markers = (
        "search_algorithms",
        "sorting/",
        "ZH1_Minta",
        "ŐSZI SZÜNET",
        "Ismétlés",
        "Monte Carlo szimulációk",
    )
    text = row_pattern.sub(
        lambda match: ""
        if (
            any(marker in match.group(0) for marker in excluded_markers)
            or (
                "I. Zárthelyi" in match.group(0)
                and "II. Zárthelyi" not in match.group(0)
            )
        )
        else match.group(0),
        text,
    )

    rows = [row for row in row_pattern.findall(text) if "<th" not in row.lower()]
    rewritten_rows = []
    for row in rows:
        compact_row = " ".join(row.split())

        def set_week(number):
            return re.sub(
                r"(<td[^>]*>\s*)[^<]*(\s*</td>)",
                rf"\g<1>{number}.\g<2>",
                row,
                count=1,
                flags=re.IGNORECASE,
            )

        if "module/index.html" in compact_row:
            row = set_week(6)
        elif "Pandas I." in compact_row:
            row = set_week(7)
        elif "Pandas II." in compact_row:
            row = set_week(8)
        elif "plotly/index.html" in compact_row:
            row = set_week(9)
        elif "practice/index.html" in compact_row:
            row = set_week(11)
        elif "II. Zárthelyi" in compact_row:
            row = row.replace("II. Zárthelyi", "Midterm")

        rewritten_rows.append(row)
        if "function/index.html" in compact_row:
            rewritten_rows.append(
                "<tr>\n"
                "<td style=\"text-align: center;\">5.</td>\n"
                "<td style=\"text-align: left;\"><strong>Ismétlés</strong></td>\n"
                "</tr>"
            )
        if "Adatvizualizáció" in row:
            rewritten_rows.append(
                "<tr>\n"
                "<td style=\"text-align: center;\">10.</td>\n"
                "<td style=\"text-align: left;\"><strong>Monte Carlo szimulációk</strong></td>\n"
                "</tr>"
            )

    table_match = re.search(
        r"(?P<open><table>.*?<tbody>).*?(?P<close></tbody>.*?</table>)",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    if table_match:
        text = (
            text[:table_match.start()]
            + table_match.group("open")
            + "\n".join(rewritten_rows)
            + table_match.group("close")
            + text[table_match.end():]
        )
    index_path.write_text(text, encoding="utf-8")


def write_root_course_index():
    source_path = OUTPUT_ROOT / "python_psz" / "index.html"
    target_path = OUTPUT_ROOT / "index.html"
    if not source_path.exists():
        return

    text = source_path.read_text(encoding="utf-8")

    text = re.sub(
        r"\s*<p>\s*<a href=\"(?:introduction/index\.html|\.\./python_basic/installation/index\.html|\.\./python_basic/ipynb/index\.html)\">.*?</p>",
        "",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    text = re.sub(
        r"<title>.*?</title>",
        "<title>Fundamentals of Programming by Burka Dávid</title>",
        text,
        count=1,
        flags=re.DOTALL | re.IGNORECASE,
    )
    text = re.sub(
        r"<h1 id=\"[^\"]+\">.*?</h1>",
        "<h1 id=\"fundamentals-of-programming\">Fundamentals of Programming by Burka Dávid</h1>",
        text,
        count=1,
        flags=re.DOTALL | re.IGNORECASE,
    )

    def move_local_link(match):
        original = match.group("url")
        if original.startswith(("#", "mailto:", "javascript:", "data:")):
            return match.group(0)
        parsed = urlparse(original)
        if parsed.scheme or parsed.netloc:
            return match.group(0)
        moved = os.path.relpath(
            Path("python_psz") / original,
            start=Path(".")
        ).replace(os.sep, "/")
        return f"{match.group('prefix')}{moved}{match.group('suffix')}"

    text = re.sub(
        r'(?P<prefix>\b(?:href|src)\s*=\s*["\'])(?P<url>[^"\']+)(?P<suffix>["\'])',
        move_local_link,
        text,
        flags=re.IGNORECASE,
    )
    target_path.write_text(text, encoding="utf-8")


def write_directory_indexes():
    directories = [OUTPUT_ROOT]
    directories.extend(sorted(path for path in OUTPUT_ROOT.rglob("*") if path.is_dir()))
    for directory in directories:
        index_path = directory / "index.html"
        if index_path.exists():
            continue

        entries = []
        if directory != OUTPUT_ROOT:
            parent_relative = os.path.relpath(
                directory.parent / "index.html", start=directory
            ).replace(os.sep, "/")
            entries.append(f'    <li><a href="{parent_relative}">..</a></li>')

        for child in sorted(directory.iterdir(), key=lambda item: (not item.is_dir(), item.name.lower())):
            if child.name in (".DS_Store", "index.html"):
                continue
            if child.is_dir():
                href = f"{child.name}/index.html"
                label = f"{child.name}/"
            else:
                href = child.name
                label = child.name
            entries.append(f'    <li><a href="{href}">{label}</a></li>')

        title = (
            f"Index of /{directory.relative_to(OUTPUT_ROOT).as_posix()}"
            if directory != OUTPUT_ROOT
            else "Index of /"
        )
        html = """<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title}</title>
</head>
<body>
    <main>
        <h1>{title}</h1>
        <ul>
{items}
        </ul>
    </main>
</body>
</html>
""".format(title=title, items="\n".join(entries))
        index_path.write_text(html, encoding="utf-8")


def main():
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    downloaded, errors = ([], []) if INDEX_ONLY else crawl()
    remove_rows_from_reduced_index()
    write_root_course_index()
    if not INDEX_ONLY:
        write_directory_indexes()
    mode = "Recreated indexes" if INDEX_ONLY else f"Downloaded {len(downloaded)} files"
    print(f"{mode} in {OUTPUT_ROOT}")
    if errors:
        print(f"Encountered {len(errors)} fetch errors:")
        for url, message in errors[:20]:
            print(f"- {url} :: {message}")


if __name__ == "__main__":
    main()
