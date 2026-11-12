# Supabase 설정 안내 (2단계)

PIECENOA 프로젝트: `piecenoa-market` (주소 `https://hqmzksyaktkpvpnugzpf.supabase.co`)

아래 순서대로 하면 돼요. 각 단계는 Supabase 대시보드(https://supabase.com/dashboard)에서 해요.

---

## 1. 데이터베이스 구조 적용

두 방법 중 하나를 고르세요.

**방법 A: Claude에게 맡기기 (추천)**
Claude가 Supabase 마이그레이션을 실행하려고 할 때 승인 창이 뜨면 허용해 주세요.
그러면 아래 두 파일을 순서대로 적용하고 기록까지 남겨요.

**방법 B: 직접 붙여 넣기**
1. 대시보드 왼쪽 메뉴 **SQL Editor** → **New query**
2. `supabase/migrations/20261112100000_record_nickname_feature.sql` 내용을 전부 복사해서 붙여 넣고 **Run**
3. 새 쿼리를 열고 `supabase/migrations/20261112100100_marketplace_schema.sql` 내용을 붙여 넣고 **Run**
4. 오류가 나면 아무것도 바뀌지 않아요. 오류 문장을 Claude에게 보여 주세요.

되돌리기가 필요하면 `supabase/rollback/20261112100100_marketplace_schema.down.sql`을 같은 방법으로 실행해요.
(새로 추가된 정보는 지워지니 꼭 필요할 때만 쓰세요.)

---

## 2. 로그인 기본 설정

**Authentication → URL Configuration**
- **Site URL**: 실제 도메인 (예: `https://piecenoa.com`). 배포 전이라면 `http://localhost:3000`
- **Redirect URLs**에 아래를 모두 추가해요. 이메일 인증, 비밀번호 재설정, Google 로그인 뒤에 돌아올 주소예요.
  - `http://localhost:3000/`
  - `https://<실제 도메인>/`
  - Vercel 미리보기 주소를 쓴다면 `https://*-<팀이름>.vercel.app/`

**Authentication → Sign In / Providers → Email**
- **Confirm email**: 켜기 (가입 후 이메일 인증을 해야 로그인돼요)
- **Minimum password length**: 8
- **Leaked password protection**: 켜기 (유출된 비밀번호 차단. Pro 요금제부터 가능해요)

---

## 3. 이메일 발송 서비스 연결 (실제 서비스 전에 꼭 필요)

Supabase 기본 메일은 **시간당 몇 통**만 보낼 수 있어서 실제 사용자를 받기에는 부족해요.

1. 메일 발송 서비스에 가입해요 (예: Resend, Postmark, Amazon SES).
2. 도메인 인증(DNS 설정)을 마쳐요. 서비스가 안내하는 대로 하면 돼요.
3. Supabase **Authentication → Emails → SMTP Settings**에서 **Enable custom SMTP**를 켜고 서비스가 준 값을 넣어요.
   - Sender email 예: `no-reply@piecenoa.com`
   - Sender name: `PIECENOA`

---

## 4. Google 로그인

**4-1. Google Cloud에서 키 만들기**
1. https://console.cloud.google.com 에서 프로젝트를 만들어요.
2. **APIs & Services → OAuth consent screen**: 앱 이름 `PIECENOA`, 지원 이메일, 도메인을 입력해요.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   - Application type: **Web application**
   - **Authorized JavaScript origins**: `http://localhost:3000`, `https://<실제 도메인>`
   - **Authorized redirect URIs**: `https://hqmzksyaktkpvpnugzpf.supabase.co/auth/v1/callback`
4. 만들어진 **Client ID**와 **Client secret**을 복사해요.

**4-2. Supabase에 넣기**
- **Authentication → Sign In / Providers → Google**을 켜고 Client ID와 Client secret을 붙여 넣어요.
- 켜면 로그인 창에 **Continue with Google** 버튼이 자동으로 나타나요. 꺼져 있으면 버튼이 숨겨져요.

Client secret은 Supabase에만 넣어요. 사이트 코드나 Vercel에는 넣지 마세요.

---

## 5. 회원 탈퇴 서버 함수 배포

1. **Edge Functions → Deploy a new function → Via Editor**
2. 함수 이름: `delete-account`
3. `supabase/functions/delete-account/index.ts` 내용을 붙여 넣고 **Deploy**
4. **Edge Functions → Secrets**에 추가해요.
   - 이름 `ALLOWED_ORIGINS`
   - 값 `http://localhost:3000,https://<실제 도메인>`

서비스 롤 키는 Supabase가 이 함수에 자동으로 넣어 줘요. 직접 어디에도 붙여 넣지 마세요.

---

## 6. 내 컴퓨터에서 실행

```
cd ~/piecenoa
node tools/write-config.mjs     # .env.local 값으로 public/js/config.js를 만들어요
npx serve public                # http://localhost:3000
```

`.env.local`에는 공개용 키(`sb_publishable_...`)만 들어 있어요. 비밀 키를 넣으면 스크립트가 거부해요.

---

## 7. Vercel 배포할 때

**Project Settings → Environment Variables**에 두 값을 넣어요.

| 이름 | 값 |
|---|---|
| `SUPABASE_URL` | `https://hqmzksyaktkpvpnugzpf.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase **Project Settings → API Keys**의 Publishable key |

배포할 때 `vercel.json`의 빌드 명령이 이 값으로 `config.js`를 만들어요.
값을 안 넣으면 사이트는 미리보기 모드로 열려요. 깨지지 않아요.

---

## 8. 관리자

- 관리자 화면: 사이트 주소 뒤에 `/admin.html` (예: `http://localhost:3000/admin.html`)
- 사이트에서 관리자 계정으로 로그인한 뒤 열면 돼요. 관리자가 아니면 "관리자만 볼 수 있는 페이지예요"가 떠요.
- 관리자 추가는 **SQL Editor에서만** 할 수 있어요. 사이트나 API로는 바꿀 수 없어요.

```
insert into public.admin_users (user_id, note)
select id, '추가한 이유' from auth.users where lower(email) = '추가할이메일@example.com';
```

- 관리자 빼기: `delete from public.admin_users where user_id = (select id from auth.users where lower(email) = '이메일');`

## 9. 보안 헤더 (배포 후)

`vercel.json`의 `Content-Security-Policy-Report-Only`는 처음에는 **검사만** 해요.
배포한 뒤 브라우저 개발자 도구의 콘솔에 `Content Security Policy` 경고가 없으면,
이름을 `Content-Security-Policy`로 바꿔서 실제로 막게 하세요.
Supabase 프로젝트 주소가 바뀌면 이 줄의 주소도 같이 바꿔야 해요.
