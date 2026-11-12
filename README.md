# PIECENOA

Global art marketplace. Static frontend (`public/`) + Supabase backend.

## 폴더 구조

```
public/                 Vercel에 올라가는 사이트
  index.html            화면 뼈대
  css/gallery.css       3D 갤러리·공통 스타일
  css/market.css        마켓 스타일
  js/vendor/three.min.js
  js/gallery.js         3D 갤러리, 로그인 창
  js/app.js             마켓 기능
  assets/               글꼴, 그림, 3D 모델
tools/
  split-single-html.py  원래 한 파일짜리 HTML을 나눈 스크립트
  split-manifest.json   나눈 파일 목록
```

## 내 컴퓨터에서 보기

3D 모델을 파일로 불러오기 때문에 `index.html`을 더블클릭하면 갤러리가 안 보일 수 있어요.
터미널에서 아래 명령을 실행한 뒤 브라우저에서 http://localhost:3000 을 여세요.

```
npx serve public
```

## 백업과 되돌리기

- 원본 한 파일짜리 HTML: `~/piecenoa-backup/piecenoa-original-2026-11-12.html`
  (지문: `piecenoa-original-2026-11-12.sha256`)
- 코드 변경 기록: git. 이전 상태 보기는 `git log`, 특정 파일 되돌리기는 `git checkout <커밋> -- <파일>`.
- 원본 HTML에서 다시 나누기: `python3 -I tools/split-single-html.py <원본.html> public`
  (그 뒤 `js/gallery.js`의 모델 로더 수정을 다시 적용해야 해요. 커밋 기록 참고.)
