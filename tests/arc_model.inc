read -ra FLAGS <<< "$("$CONFIG" --objc-flags)"
read -ra LIBS <<< "$("$CONFIG" --base-libs)"
RPATHS=()
for flag in "${LIBS[@]}"; do
    [[ "$flag" != -L* ]] || RPATHS+=("-Wl,-rpath,${flag#-L}")
done
"${CC:-clang}" "${FLAGS[@]}" -fobjc-arc -fblocks -Wno-unused-parameter \
    -I"$ROOT/tests" -I"$ROOT/src" -I"$OUT" \
    "$ROOT/src/Models.m" "$ROOT/src/AnnotationFiles.m" "$ROOT/tests/UIKit.m" "$ROOT/tests/$1.m" \
    -o "$OUT/$1" "${LIBS[@]}" "${RPATHS[@]}"
"$OUT/$1"
