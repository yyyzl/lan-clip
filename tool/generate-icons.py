"""Export Lan Clip's geometric mark to native icons. Requires Pillow.

All platforms share these coordinates; no font, network or raster source is used.
Run from any directory with Python 3 and Pillow installed.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[1]
GREEN, SAGE, PAPER = '#256D53', '#A7C6B5', '#F6F7F3'
SCALE = 3


def mark(background=True, template=False):
    canvas = Image.new('RGBA', (1024*SCALE, 1024*SCALE))
    draw = ImageDraw.Draw(canvas)
    def rect(box, radius, fill):
        draw.rounded_rectangle(tuple(v*SCALE for v in box), radius=radius*SCALE, fill=fill)
    if background:
        rect((56, 56, 968, 968), 210, GREEN)
    rect((234, 202, 610, 664), 62, (0, 0, 0, 150) if template else SAGE)
    rect((400, 342, 790, 822), 62, '#000000' if template else PAPER)
    color = (0, 0, 0, 0) if template else GREEN
    paths = [[(490, 582), (701, 582)], [(633, 514), (701, 582), (633, 650)]]
    for points in paths:
        draw.line([(x*SCALE, y*SCALE) for x, y in points], fill=color, width=42*SCALE, joint='curve')
        for x, y in points:
            draw.ellipse(((x-21)*SCALE, (y-21)*SCALE, (x+21)*SCALE, (y+21)*SCALE), fill=color)
    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def save(image, path, size):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)


icon = mark()
icon.save(ROOT/'design/app-icon.png')
icon.save(ROOT/'design/AppIcon.icns', format='ICNS')
(ROOT/'design/app-icon.svg').write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>轻贴 — 两张纸与向右发送箭头</title>
  <rect x="56" y="56" width="912" height="912" rx="210" fill="{GREEN}"/>
  <rect x="234" y="202" width="376" height="462" rx="62" fill="{SAGE}"/>
  <rect x="400" y="342" width="390" height="480" rx="62" fill="{PAPER}"/>
  <path d="M490 582H701M633 514L701 582L633 650" fill="none" stroke="{GREEN}" stroke-width="42" stroke-linecap="round" stroke-linejoin="round"/>
</svg>\n''')
save(icon, 'assets/brand/icon.png', 256)
icon.save(ROOT/'windows/runner/resources/app_icon.ico', format='ICO', sizes=[(16,16),(20,20),(24,24),(32,32),(40,40),(48,48),(64,64),(128,128),(256,256)])
for bucket, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    save(icon, f'android/app/src/main/res/mipmap-{bucket}/ic_launcher.png', size)
assets=ROOT/'macos/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((assets/'Contents.json').read_text())['images']:
    if 'filename' in item:
        size=int(float(item['size'].split('x')[0])*int(item['scale'][0]))
        save(icon, assets/item['filename'], size)

# Template images let macOS choose a readable menu-bar color in light/dark mode.
status = mark(background=False, template=True).crop((196, 164, 828, 860))
status_assets = ROOT/'macos/Runner/Assets.xcassets/StatusIcon.imageset'
status_assets.mkdir(parents=True, exist_ok=True)
entries=[]
for scale in (1, 2):
    filename=f'status-{scale}x.png'
    status.resize((16*scale, 18*scale), Image.Resampling.LANCZOS).save(status_assets/filename)
    entries.append({'idiom':'mac', 'scale':f'{scale}x', 'filename':filename})
(status_assets/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1},'properties':{'template-rendering-intent':'template'}}, indent=2)+'\n')
# Standalone local runner has no compiled asset catalogue.
status.resize((32, 36), Image.Resampling.LANCZOS).save(ROOT/'design/StatusIcon.png')

# Android adaptive icons retain the same glyph across circle/squircle masks.
res=ROOT/'android/app/src/main/res'
(res/'values/colors.xml').write_text(f'<resources><color name="icon_background">{GREEN}</color><color name="launch_background">{PAPER}</color></resources>\n')
vector=f'''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
    <path android:fillColor="{SAGE}" android:pathData="M296,202H548Q610,202 610,264V602Q610,664 548,664H296Q234,664 234,602V264Q234,202 296,202Z"/>
    <path android:fillColor="{PAPER}" android:pathData="M462,342H728Q790,342 790,404V760Q790,822 728,822H462Q400,822 400,760V404Q400,342 462,342Z"/>
    <path android:fillColor="@android:color/transparent" android:strokeColor="{GREEN}" android:strokeWidth="42" android:strokeLineCap="round" android:strokeLineJoin="round" android:pathData="M490,582H701M633,514L701,582L633,650"/>
</vector>\n'''
(res/'drawable/ic_launcher_foreground.xml').write_text(vector)
# Even-odd holes keep the transfer arrow visible in themed monochrome icons.
(res/'drawable/ic_launcher_monochrome.xml').write_text('''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" android:pathData="M296,202H548Q610,202 610,264V310H462Q368,310 368,404V664H296Q234,664 234,602V264Q234,202 296,202Z M462,342H728Q790,342 790,404V760Q790,822 728,822H462Q400,822 400,760V404Q400,342 462,342Z M490,561H650L618,529L648,499L731,582L648,665L618,635L650,603H490Z"/>
</vector>\n''')
for api in (26, 33):
    folder=res/f'mipmap-anydpi-v{api}'
    folder.mkdir(parents=True, exist_ok=True)
    mono='\n    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if api>=33 else ''
    (folder/'ic_launcher.xml').write_text(f'''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>{mono}
</adaptive-icon>\n''')
print('Exported shared SVG/PNG, Windows ICO, macOS ICNS/menu bar and Android adaptive icons.')
