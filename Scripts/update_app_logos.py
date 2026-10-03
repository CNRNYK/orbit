#!/usr/bin/env python3
"""Collect raster site icons linked by official project homepages (no icon aggregators)."""
import concurrent.futures, hashlib, json, pathlib, re, urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
ROOT = pathlib.Path(__file__).resolve().parents[1]
class Icons(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'link' and 'icon' in attrs.get('rel', '').lower() and attrs.get('href'):
            self.links.append((0 if 'apple-touch' in attrs.get('rel', '') else 1, attrs['href']))
def fetch(url, limit):
    if urlparse(url).scheme != 'https': raise ValueError('HTTPS required')
    req = urllib.request.Request(url, headers={'User-Agent': 'Orbit-Catalog/0.5'})
    with urllib.request.urlopen(req, timeout=8) as response:
        if urlparse(response.url).scheme != 'https': raise ValueError('Insecure redirect')
        data = response.read(limit + 1)
        if len(data) > limit: raise ValueError('Asset too large')
        return data, response.url
def repository_icon(package):
    repository = package.get('github')
    if not repository: return package['token'], {}, None
    path = urlparse(repository).path.strip('/')
    if len(path.split('/')) != 2: return package['token'], {}, None
    for branch in ('main', 'master'):
        readme = f'https://raw.githubusercontent.com/{path}/{branch}/README.md'
        try:
            content, _ = fetch(readme, 1000000)
            text = content.decode('utf-8', errors='replace')
            candidates = re.findall(r'!\[([^\]]*)\]\(([^ )]+)', text)
            candidates += [(a, b) for b, a in re.findall(r'<img[^>]*src=["\']([^"\']+)["\'][^>]*alt=["\']([^"\']*)', text)]
            for label, href in candidates:
                if not re.search(r'logo|icon', label + ' ' + href, re.I): continue
                url = urljoin(readme, href)
                if urlparse(url).path.lower().endswith('.svg'): continue
                try:
                    data, resolved = fetch(url, 1000000)
                    if data.startswith(b'\x89PNG\r\n\x1a\n'): ext = 'png'
                    elif data.startswith(b'\x00\x00\x01\x00'): ext = 'ico'
                    elif data.startswith(b'\xff\xd8\xff'): ext = 'jpg'
                    else: continue
                    filename = hashlib.sha256(package['token'].encode()).hexdigest()[:24] + '.' + ext
                    return package['token'], {'logoURL': resolved, 'logoSource': readme, 'logoAsset': filename}, data
                except Exception: pass
        except Exception: pass
    return package['token'], {}, None
def collect(package):
    homepage = package['homepage']
    # Hosting-service favicons are not the hosted application's logo.
    if urlparse(homepage).hostname in ('github.com', 'apps.apple.com', 'gitlab.com'):
        return repository_icon(package)
    try:
        html, page = fetch(homepage, 2000000)
        parser = Icons(); parser.feed(html.decode('utf-8', errors='replace'))
        candidates = [urljoin(page, href) for _, href in sorted(parser.links)]
        candidates += [urljoin(page, '/favicon.ico')]
        for url in dict.fromkeys(candidates):
            if urlparse(url).path.lower().endswith('.svg'): continue
            try:
                data, resolved = fetch(url, 1000000)
                if data.startswith(b'\x89PNG\r\n\x1a\n'): ext = 'png'
                elif data.startswith(b'\x00\x00\x01\x00'): ext = 'ico'
                elif data.startswith(b'\xff\xd8\xff'): ext = 'jpg'
                else: continue
                filename = hashlib.sha256(package['token'].encode()).hexdigest()[:24] + '.' + ext
                return package['token'], {'logoURL': resolved, 'logoSource': page, 'logoAsset': filename}, data
            except Exception: pass
    except Exception: pass
    return repository_icon(package)
if __name__ == '__main__':
    path = ROOT / 'Resources/catalog.json'; catalog = json.loads(path.read_text())
    packages = {p['token']: p for p in catalog['packages']}; count = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        for i, (token, metadata, data) in enumerate(executor.map(collect, packages.values()), 1):
            for key in ('logoURL', 'logoSource', 'logoAsset'): packages[token].pop(key, None)
            packages[token].update(metadata)
            if data:
                (ROOT / 'Resources/Logos' / metadata['logoAsset']).write_bytes(data); count += 1
            if i % 50 == 0: print(f'Checked {i}/{len(packages)}; found {count} official site icons', flush=True)
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    print(f'Bundled {count} official site icons; remaining entries use installed-app or category icons.', flush=True)
