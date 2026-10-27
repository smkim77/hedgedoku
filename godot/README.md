# 고슴도쿠 (Godot)

웹 버전 고슴도쿠를 Godot 4로 옮긴 버전입니다. 규칙, 퍼즐 생성, 도전/연습 모드, 프로필, 리더보드(전체 · 이번 주)가 웹 버전과 같습니다.
같은 퍼즐 생성 코드를 그대로 옮겨서, 연습 모드의 레벨은 웹 버전과 똑같은 판이 나옵니다.

**플레이: https://smkim77.github.io/hedgedoku/play/**

## 파일

- `main.gd`: 게임 상태와 규칙, 화면 전체(코드로 구성), 리더보드·프로필·규칙·도전 끝내기 창
- `board.gd`: 퍼즐 보드 그리기와 입력(탭, 더블탭, 드래그, 키보드), 가시·× 애니메이션
- `puzzle.gd`: 퍼즐 생성 (웹 버전과 같은 결과가 나오도록 32비트 정수 연산까지 그대로 옮김)
- `art.gd`, `drawbox.gd`: 고슴도치, 사과, 버튼 아이콘 그림
- `lb.gd`: 리더보드 서버(Supabase) 통신
- `fonts/`: Jua, Gowun Dodum (SIL OFL 1.1, `fonts/OFL-*.txt`)
- `avatars/`: 프로필 이모지 그림 — [Twemoji](https://github.com/jdecked/twemoji) (CC-BY 4.0). 웹 내보내기에는 이모지 폰트가 없어서 그림으로 넣었습니다.
- `export_presets.cfg`: 웹 내보내기 설정 (`Web` 프리셋, 결과는 저장소의 `../play/`)

## 고친 뒤 내보내기

Godot 4.7.2(표준판)에서 이 폴더를 열고 `Web` 프리셋으로 내보내거나, 명령줄에서:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path godot --export-release "Web" ../play/index.html
```

그다음 `play/`도 함께 커밋하세요.

## 리더보드

웹 버전과 같은 Supabase 리더보드를 씁니다. 서버는 게임 주소(smkim77.github.io)에서 온 기록만 받으므로,
그 주소의 웹 빌드에서만 온라인 기록이 올라갑니다. PC에서 실행하거나 다른 주소에서 열면 이 기기의 기록만 보여요.
프로필(플레이어 ID)은 웹 버전과 따로 저장됩니다.

시험용: `localhost`에서 `?sb=http://127.0.0.1:포트`를 붙이면 그 주소의 가짜 서버로 리더보드를 시험할 수 있고, F9로 지금 레벨을 바로 풀 수 있습니다.
