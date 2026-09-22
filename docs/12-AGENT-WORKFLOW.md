# 12 — Agent workflow: watch-build / watch-git

Agent (Claude) **không có shell trên máy bạn** — nó chỉ đọc/ghi được file trong
các connected folder. Nên toàn bộ build, test, git được "đặt hàng" qua file,
giống hệt cách đang làm với SnapTool.

## Scripts đã tạo

```
App/oneai/scripts/
  build-and-test.sh     flutter pub get → (build_runner) → analyze → test → build
  watch-build.sh        chờ .build-request → chạy build-and-test.sh → ghi .build-done
  watch-git.sh          chờ .git-request  → chạy git       → ghi .git-done

Backend/oneai_backend/scripts/
  build-and-test.sh     node --check v1 → eslint + tsc + vitest trên functions-v2/
  watch-build.sh        giống trên
  watch-git.sh          giống trên
```

## Chạy 1 lần, để mở (4 tab Terminal)

```bash
cd /Volumes/DOXUTO_SSDBOX/workspace/oneai/App/oneai_v2          && bash scripts/watch-build.sh
cd /Volumes/DOXUTO_SSDBOX/workspace/oneai/App/oneai_v2          && bash scripts/watch-git.sh
cd /Volumes/DOXUTO_SSDBOX/workspace/oneai/Backend/oneai_backend && bash scripts/watch-build.sh
cd /Volumes/DOXUTO_SSDBOX/workspace/oneai/Backend/oneai_backend && bash scripts/watch-git.sh
```

> Trỏ vào `oneai_v2`, không phải `oneai`. `App/oneai/scripts/` vẫn còn nhưng
> chỉ dùng nếu cần build lại bản legacy để đối chiếu.

**Phạm vi trong monorepo.** Workspace là một repo ở thư mục gốc, nên cả hai
watcher `watch-git` đều thao tác trên repo đó. Để tab App không commit nhầm
thay đổi của Backend, `git add` được giới hạn vào thư mục chứa script:

```bash
git add -A -- "$PROJECT_DIR"
```

Muốn commit cả workspace trong một lần thì dùng `#cmd:` với đường dẫn tường minh.

## Giao thức

### Build

| Bước | Ai | Việc |
|---|---|---|
| 1 | agent | ghi `.build-request` (dòng đầu = tham số, có thể rỗng) |
| 2 | watcher | đọc → xoá request → chạy `scripts/build-and-test.sh <args>` |
| 3 | watcher | ghi `.build-done` gồm `exit=`, `report=`, `finished=` |
| 4 | agent | đọc `.build-done`, rồi đọc `reports/latest/summary.md` |

Tham số app:

```bash
echo ""                            > .build-request   # analyze + test + build ios
echo "--analyze-only"              > .build-request
echo "--test-only"                 > .build-request
echo "--codegen --no-build"        > .build-request   # build_runner + analyze + test
echo "--android"                   > .build-request
echo "MIN_TESTS=20 --test-only"    > .build-request   # VAR=value ở đầu → env
```

Tham số backend:

```bash
echo ""              > .build-request   # v1 syntax check + lint + build + test v2
echo "--lint-only"   > .build-request
echo "--test-only"   > .build-request
echo "--v1-check"    > .build-request
```

### Git

```bash
# commit: nội dung file = commit message
printf '%s\n' "[feat][be] Add createMinute callable" > .git-request

# chạy lệnh git bất kỳ trong whitelist
echo "#cmd:status --short"        > .git-request
echo "#cmd:log --oneline -10"     > .git-request
echo "#cmd:diff --stat"           > .git-request
echo "#cmd:checkout -b feat/be-v2" > .git-request
```

Whitelist: `status log diff add commit branch checkout switch stash pull push
restore rm mv tag fetch show rev-parse`. Muốn tự tay đẩy code, xoá `push` khỏi
biến `ALLOWED` trong `watch-git.sh`.

## Quy tắc làm việc của agent

1. **Một task → một commit.** Message theo format `[type][scope] Mô tả`
   (`[feat][be]`, `[fix][app]`, `[chore][docs]`, `[test][be]`).
   Không đổi git author, không thêm trailer `Co-Authored-By`.
2. **Build xanh mới chuyển task.** Sau mỗi task: ghi `.build-request` → đọc
   `.build-done` → nếu `exit≠0` thì sửa lỗi ngay, không sang task kế tiếp.
3. **Fix bug trước, thêm feature sau** trong cùng một sprint.
4. Comment trong code viết bằng **tiếng Anh**.
5. Mọi thứ chưa được confirm → ghi vào `docs/11-OPEN-QUESTIONS.md`, không tự quyết.
6. **KHÔNG deploy.** `firebase deploy` do người chạy.

## Báo cáo

`reports/`, `.build-request`, `.build-done`, `.git-request`, `.git-done` đều bị
gitignore ở repo gốc. Mỗi lần chạy sinh `reports/<yyyymmdd-HHMMSS>/` gồm
`summary.md` + log từng bước, và `reports/latest` là symlink tới lần mới nhất.
