#!/usr/bin/env python3
"""Enrich the catalog from official Homebrew metadata and project homepages.

Usage: python3 Scripts/update_package_links.py --metadata-dir /path/to/api-cache
A GitHub repository is accepted only from package metadata or a project-name
matching link on the official homepage. Missing links remain explicitly unknown.
"""
import argparse, concurrent.futures, html, json, re, urllib.parse, urllib.request
from pathlib import Path
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[1]

def normalize(value):
    return re.sub(r'[^a-z0-9]', '', value.lower())

def github_repository(url):
    if not isinstance(url, str): return None
    parsed = urllib.parse.urlparse(url)
    if parsed.hostname not in {'github.com', 'www.github.com', 'raw.githubusercontent.com', 'codeload.github.com'}: return None
    parts = parsed.path.strip('/').split('/')
    if len(parts) < 2: return None
    owner, repo = parts[:2]; repo = re.sub(r'\.git$', '', repo)
    if owner.lower() in {'homebrew', 'sponsors', 'features', 'topics', 'settings', 'orgs', 'login', 'marketplace'}: return None
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', owner) or not re.fullmatch(r'[A-Za-z0-9_.-]+', repo): return None
    return f'https://github.com/{owner}/{repo}'

class Links(HTMLParser):
    def __init__(self): super().__init__(); self.links=[]
    def handle_starttag(self, tag, attributes):
        if tag=='a':
            link=dict(attributes).get('href')
            if link:self.links.append(link)

def official_page_candidates(package):
    homepage=package.get('homepage')
    if not homepage:return []
    try:
        request=urllib.request.Request(homepage, headers={'User-Agent':'MacSetupCatalog/0.4 (+Homebrew package links)'})
        with urllib.request.urlopen(request, timeout=12) as response:
            content=response.read(1_500_000).decode('utf-8',errors='replace')
        parser=Links();parser.feed(content)
        names={normalize(package['token'].split('@')[0]),normalize(package['name'])}
        names.discard('')
        result=[]
        for link in parser.links:
            repo=github_repository(urllib.parse.urljoin(homepage,html.unescape(link)))
            if not repo:continue
            slug=normalize(repo.rsplit('/',1)[-1])
            if slug in names or any(len(n)>=4 and (slug==n+'app' or slug==n+'desktop') for n in names):
                if repo not in result:result.append(repo)
        return result
    except Exception:return []

def main():
    args=argparse.ArgumentParser();args.add_argument('--metadata-dir',type=Path,required=True);options=args.parse_args()
    metadata={}
    for kind in ['cask','formula']:
        for item in json.loads((options.metadata_dir/f'{kind}.json').read_text()):
            metadata[(kind,item['token'] if kind=='cask' else item['name'])]=item
    file=ROOT/'Resources/catalog.json';catalog=json.loads(file.read_text())
    site_fixes={
        'Sleep Control Center':'https://prevent-mac-from-sleeping.3bitlab.com/prevent_mac_sleep_help.html',
        'SerialTools':'https://apps.apple.com/app/serialtools/id611021963'}
    missing=[]
    for package in catalog['packages']:
        if package['name'] in site_fixes:
            package['homepage']=site_fixes[package['name']]
            package['homepageSource']=site_fixes[package['name']]
        kind='cask' if package['cask'] else 'formula'
        info=metadata.get((kind,package['token']),{})
        urls=[]
        if package.get('homepage'):urls.append(package['homepage'])
        if info.get('url'):urls.append(info['url'])
        for value in info.get('urls',{}).values():
            if isinstance(value,dict) and value.get('url'):urls.append(value['url'])
        package['github']=None;package['githubSource']=None
        for url in urls:
            repo=github_repository(url)
            if repo:
                package['github']=repo
                package['githubSource']=f"https://formulae.brew.sh/api/{kind}/{package['token']}.json" if info else package['homepage']
                break
        if not package['github']:missing.append(package)
        if info:
            package['homepageSource']=f"https://formulae.brew.sh/api/{kind}/{package['token']}.json"
            package['version']=info.get('version') or info.get('versions',{}).get('stable')
        package.setdefault('homepageSource',package.get('homepage'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        for package,candidates in zip(missing,pool.map(official_page_candidates,missing)):
            if len(candidates)==1:
                package['github']=candidates[0];package['githubSource']=package['homepage']
    curated=json.loads((ROOT/'Scripts/verified_github_links.json').read_text())
    for package in catalog['packages']:
        if package['name'] in curated:
            url,purpose=curated[package['name']]
            package['github']=url;package['githubSource']=url;package['githubPurpose']=purpose
    file.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    verified=sum(bool(p.get('github')) for p in catalog['packages'])
    print(f"Official website: {sum(bool(p.get('homepage')) for p in catalog['packages'])}/{len(catalog['packages'])}; evidence-backed GitHub links: {verified}")
    print('GitHub links not verified:',len(catalog['packages'])-verified)

if __name__=='__main__':main()
