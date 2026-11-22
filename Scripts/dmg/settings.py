# -*- coding: utf-8 -*-
# PomoLight DMG 설치 창 설정 — dmgbuild 가 읽는다 (2026-11-22, #11). Scripts/make_dmg.sh 가 부른다.
#
# 🚨 왜 dmgbuild 인가: 창 모양(배경·아이콘 위치·창 크기)은 DMG 안의 .DS_Store 에 저장되는데, 그걸 만드는
#    정상 경로인 Finder AppleScript 의 "배경 그림 지정"이 macOS 27 에서 깨져 있다(설정은 오류 없이 무시 —
#    닦아 2026-09-22 실측). dmgbuild 는 Finder 를 거치지 않고 .DS_Store 를 직접 쓴다.
#    1.6.7 아래는 macOS 26.2 회귀(FB21405103)로 배경이 안 보이는 DMG 를 조용히 만든다 — make_dmg.sh 가 버전을 막는다.
# 🔒 window_rect 크기와 icon_locations 는 Scripts/dmg/background.swift 의 W x H · 아이콘 중심과 같아야 한다.
import os.path

application = defines.get("app", "dist/PomoLight.app")
appname = os.path.basename(application)

format = "UDZO"
# compression_level: dmgbuild 2.0 ignores it (FutureWarning) — UDZO's default is used.
size = None

files = [application]
symlinks = {"Applications": "/Applications"}

background = defines.get("background", "background.tiff")

window_rect = ((200, 120), (640, 440))
default_view = "icon-view"
icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None   # 자동 정렬을 켜 두면 아래 좌표가 무시된다

icon_locations = {
    appname: (165, 195),
    "Applications": (475, 195),
}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
