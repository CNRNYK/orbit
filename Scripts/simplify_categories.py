#!/usr/bin/env python3
"""Migrate the legacy 27-category catalog to the purpose-based navigation taxonomy."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = {
 'AI': ('sparkles', 'Assistants, coding agents and tools for working with AI.'),
 'Development': ('chevron.left.forwardslash.chevron.right', 'Editors, languages and tools for building software.'),
 'Cloud & Databases': ('cloud', 'Containers, cloud infrastructure and database tools.'),
 'Design & Media': ('paintpalette', 'Create and edit graphics, photos, video, audio and 3D.'),
 'Productivity': ('checkmark.circle', 'Notes, documents and tools for everyday work.'),
 'Communication': ('bubble.left.and.bubble.right', 'Messaging, meetings and tools for staying connected.'),
 'Browsers & Internet': ('globe', 'Browse the web and manage downloads.'),
 'Files & Storage': ('folder', 'Organize, sync, transfer and archive your files.'),
 'Mac Utilities': ('slider.horizontal.3', 'Customize, automate and maintain your Mac.'),
 'Security & Networking': ('lock.shield', 'Passwords, privacy, VPNs and network diagnostics.')
}
MAPPING = {
 'Google': ('Files & Storage', 'Cloud Storage & Sync'),
 'Mac Power Tools': ('Mac Utilities', 'Customization & Automation'),
 'System Utilities': ('Mac Utilities', 'System & Maintenance'),
 'Files & Compression': ('Files & Storage', 'File Management'),
 'Browsers & Internet': ('Browsers & Internet', 'Web Browsers'),
 'AI & LLM': ('AI', 'Assistants'),
 'Development': ('Development', 'Terminal & CLI'),
 'Database': ('Cloud & Databases', 'Databases'),
 'DevOps & Cloud': ('Cloud & Databases', 'Cloud & Infrastructure'),
 'CLI Power Tools': ('Development', 'Terminal & CLI'),
 'Languages & Runtimes': ('Development', 'Languages & Runtimes'),
 'Networking & Debugging': ('Security & Networking', 'Network Tools'),
 'Design': ('Design & Media', 'UI & Graphic Design'),
 '3D & CAD': ('Design & Media', '3D & CAD'),
 'Photography': ('Design & Media', 'Photography'),
 'Video Production': ('Design & Media', 'Video'),
 'Audio & Music': ('Design & Media', 'Audio'),
 'Notes & Knowledge': ('Productivity', 'Notes & Knowledge'),
 'Office & PDF': ('Productivity', 'Office & PDF'),
 'Communication': ('Communication', 'Messaging & Meetings'),
 'Security & Passwords': ('Security & Networking', 'Passwords & Security'),
 'Screen Capture': ('Design & Media', 'Screen Capture'),
 'Download Managers': ('Browsers & Internet', 'Downloads'),
 'Electronics & Engineering': ('Development', 'Hardware & Embedded'),
 'GIS & Science': ('Productivity', 'Science & Research'),
 'Mobile Development': ('Development', 'Mobile Development'),
 'Hardware & Remote Access': ('Mac Utilities', 'Hardware & Remote Access')
}
SUBSYMBOLS = {
 'Assistants':'sparkles','Coding Agents':'chevron.left.forwardslash.chevron.right','Local AI & Infrastructure':'cpu',
 'Code Editors & IDEs':'curlybraces','Languages & Runtimes':'terminal','Git & Version Control':'arrow.triangle.branch',
 'Terminal & CLI':'terminal','Testing & Debugging':'ladybug','Hardware & Embedded':'cpu','Mobile Development':'iphone',
 'Containers & Virtualization':'shippingbox','Cloud & Infrastructure':'cloud','Databases':'externaldrive',
 'UI & Graphic Design':'paintpalette','Diagrams':'point.3.connected.trianglepath.dotted','Photography':'camera',
 'Video':'film','Audio':'music.note','3D & CAD':'cube','Screen Capture':'viewfinder',
 'Notes & Knowledge':'note.text','Office & PDF':'doc.text','Science & Research':'function',
 'Messaging & Meetings':'bubble.left.and.bubble.right','Web Browsers':'globe','Downloads':'arrow.down.circle',
 'File Management':'folder','Cloud Storage & Sync':'icloud','Compression':'archivebox','Storage & Transfer':'externaldrive',
 'Customization & Automation':'command','System & Maintenance':'wrench.and.screwdriver','Hardware & Remote Access':'desktopcomputer',
 'Passwords & Security':'key','VPN & Privacy':'lock.shield','Network Tools':'network'
}
def placement(old, token):
 cat, sub = old['category'], old['subcategory']
 if cat == 'Google' and token == 'google-chrome': return ('Browsers & Internet','Web Browsers')
 if cat == 'AI & LLM':
  return ('AI', 'Coding Agents' if sub == 'AI Coding Agents' else 'Local AI & Infrastructure' if sub in ('AI Developer Infrastructure','Local LLM') else 'Assistants')
 if cat == 'Development':
  if sub == 'Code Editors & IDEs': return ('Development', sub)
  if sub == 'Git & Source Control': return ('Development', 'Git & Version Control')
  if sub in ('API Development','CLI API Tools'): return ('Development','Testing & Debugging')
  if sub in ('Containers','Virtualization'): return ('Cloud & Databases','Containers & Virtualization')
 if cat == 'Networking & Debugging' and sub == 'VPN / Network': return ('Security & Networking','VPN & Privacy')
 if cat == 'Design' and sub == 'Diagram / Architecture': return ('Design & Media','Diagrams')
 if cat == 'Files & Compression':
  return ('Files & Storage', 'Compression' if sub == 'Compression' else 'Storage & Transfer' if sub in ('Disk / Storage','File Transfer') else 'File Management')
 return MAPPING[cat]
SUBORDER = {'AI': ['Assistants', 'Coding Agents', 'Local AI & Infrastructure'], 'Development': ['Code Editors & IDEs', 'Languages & Runtimes', 'Git & Version Control', 'Terminal & CLI', 'Testing & Debugging', 'Mobile Development', 'Hardware & Embedded'], 'Cloud & Databases': ['Containers & Virtualization', 'Cloud & Infrastructure', 'Databases'], 'Design & Media': ['UI & Graphic Design', 'Diagrams', 'Photography', 'Video', 'Audio', '3D & CAD', 'Screen Capture'], 'Productivity': ['Notes & Knowledge', 'Office & PDF', 'Science & Research'], 'Communication': ['Messaging & Meetings'], 'Browsers & Internet': ['Web Browsers', 'Downloads'], 'Files & Storage': ['Cloud Storage & Sync', 'File Management', 'Storage & Transfer', 'Compression'], 'Mac Utilities': ['Customization & Automation', 'System & Maintenance', 'Hardware & Remote Access'], 'Security & Networking': ['Passwords & Security', 'VPN & Privacy', 'Network Tools']}
if __name__ == '__main__':
 path = ROOT/'Resources/catalog.json'; catalog=json.loads(path.read_text())
 if catalog.get('taxonomyVersion') == 1: print('Catalog already migrated.'); raise SystemExit()
 before={p['token']: {k:v for k,v in p.items() if k!='placements'} for p in catalog['packages']}
 for package in catalog['packages']:
  mapped=list(dict.fromkeys(placement(p,package['token']) for p in package['placements']))
  if package['token'] in ('docker','colima','podman'): mapped.append(('Development','Terminal & CLI'))
  if package['token'] in ('cursor','claude-code','codex'): mapped.append(('Development','Code Editors & IDEs' if package['token']=='cursor' else 'Terminal & CLI'))
  package['placements']=[{'category':c,'subcategory':s} for c,s in dict.fromkeys(mapped)]
 catalog.update(taxonomyVersion=1,categories=list(CATEGORIES),symbols={k:v[0] for k,v in CATEGORIES.items()},categoryDescriptions={k:v[1] for k,v in CATEGORIES.items()},subcategorySymbols=SUBSYMBOLS,subcategoryOrder=SUBORDER)
 assert before=={p['token']: {k:v for k,v in p.items() if k!='placements'} for p in catalog['packages']}
 path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
 print(f'Migrated {len(catalog["packages"])} apps to {len(CATEGORIES)} categories; package metadata preserved.')
