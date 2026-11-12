# PIECENOA

Global art marketplace. Static frontend (`public/`) + Supabase backend.

## 폴더 구조

```
public/                 Vercel에 올라가는 사이트
  index.html            화면 뼈대
  css/gallery.css       3D 갤러리·공통 스타일
  css/market.css        마켓 스타일
  js/vendor/three.min.js
  js/gallery.js         3D 갤러리, 로그인 창(미리보기 모드)
  js/account.js         Supabase 로그인·회원가입·비밀번호 재설정·탈퇴
  js/config.js          자동 생성 (git에 올리지 않음)
  js/app.js             마켓 기능
  css/account.css       계정 화면 추가 스타일
  assets/               글꼴, 그림, 3D 모델
tools/
  split-single-html.py  원래 한 파일짜리 HTML을 나눈 스크립트
  split-manifest.json   나눈 파일 목록
```

## 내 컴퓨터에서 보기

3D 모델을 파일로 불러오기 때문에 `index.html`을 더블클릭하면 갤러리가 안 보일 수 있어요.
터미널에서 아래 명령을 실행한 뒤 브라우저에서 http://localhost:3000 을 여세요.

```
node tools/write-config.mjs   # .env.local로 Supabase 연결 설정 만들기 (없으면 미리보기 모드)
npx serve public
```

Supabase·Google 로그인·이메일·배포 설정은 [docs/setup-supabase.md](docs/setup-supabase.md)를 보세요.

## 데이터베이스

- `supabase/migrations/`: 순서대로 적용하는 SQL
- `supabase/rollback/`: 되돌리기 SQL
- `supabase/functions/delete-account/`: 회원 탈퇴 서버 함수

## 백업과 되돌리기

- 원본 한 파일짜리 HTML: `~/piecenoa-backup/piecenoa-original-2026-11-12.html`
  (지문: `piecenoa-original-2026-11-12.sha256`)
- 코드 변경 기록: git. 이전 상태 보기는 `git log`, 특정 파일 되돌리기는 `git checkout <커밋> -- <파일>`.
- 원본 HTML에서 다시 나누기: `python3 -I tools/split-single-html.py <원본.html> public`
  (그 뒤 `js/gallery.js`의 모델 로더 수정을 다시 적용해야 해요. 커밋 기록 참고.)
