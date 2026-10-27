# 고슴도쿠 (Godot)

고슴도쿠의 Godot 4 프로젝트입니다. 처음 HTML로 만든 버전(git 기록에 남아 있음)을 옮겨 와서 지금은 이 버전이 서비스됩니다.
퍼즐 생성 코드를 그대로 옮겨서, 연습 모드의 레벨은 예전 HTML 버전과 똑같은 판이 나옵니다.

**플레이: https://smkim77.github.io/hedgedoku/**

## 파일

- `main.gd`: 게임 상태와 규칙, 화면 전체(코드로 구성), 리더보드·프로필·규칙·도전 끝내기 창
- `board.gd`: 퍼즐 보드 그리기와 입력(탭, 더블탭, 드래그, 키보드), 가시·× 애니메이션
- `puzzle.gd`: 퍼즐 생성 (예전 HTML 버전과 같은 결과가 나오도록 32비트 정수 연산까지 그대로 옮김)
- `art.gd`, `drawbox.gd`: 고슴도치, 사과, 버튼 아이콘 그림
- `lb.gd`: 리더보드 서버(Supabase) 통신
- `fonts/`: Jua, Gowun Dodum (SIL OFL 1.1, `fonts/OFL-*.txt`)
- `avatars/`: 프로필 이모지 그림 — [Twemoji](https://github.com/jdecked/twemoji) (CC-BY 4.0). 웹 내보내기에는 이모지 폰트가 없어서 그림으로 넣었습니다.
- `export_presets.cfg`: 웹 내보내기 설정 (`Web` 프리셋, 결과는 저장소 맨 위)

## 고친 뒤 내보내기

Godot 4.7.2(표준판)에서 이 폴더를 열고 `Web` 프리셋으로 내보내거나, 명령줄에서:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path godot --export-release "Web" ../index.html
```

그다음 저장소 맨 위의 `index.*` 파일도 함께 커밋하세요.

## 리더보드

리더보드는 Supabase를 씁니다 (`../supabase/setup.sql`). 서버는 게임 주소(smkim77.github.io)에서 온 기록만 받으므로,
그 주소의 웹 빌드에서만 온라인 기록이 올라갑니다. PC에서 실행하거나 다른 주소에서 열면 이 기기의 기록만 보여요.

시험용: `localhost`에서 `?sb=http://127.0.0.1:포트`를 붙이면 그 주소의 가짜 서버로 리더보드를 시험할 수 있고, F9로 지금 레벨을 바로 풀 수 있습니다.
