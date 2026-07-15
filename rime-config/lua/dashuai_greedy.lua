-- 大帅拼音 · 最长音节切分优先过滤器
-- 原则：连续输入默认按最长音节切分（wang da shuai 优先于 wang da shu ai），
--       想要短切分请用分隔符（wang'da'shu'ai）。
-- 机制：在完整覆盖当前输入的候选中，把音节数最少（切分最整）的候选提到最前。
--       仅当语言模型选了"更碎"的切分时才会触发换位，其余情况零干预。
-- 只在纯中文候选之间比较：英文/混输候选的 preedit 没有音节空格，
-- 会被误判成"1 音节"抢到首位（如 buju 首选变 Bujumbura），必须排除。

local function syllable_count(preedit)
  if not preedit or preedit == "" then return nil end
  local n = 1
  for _ in string.gmatch(preedit, "[%s']+") do
    n = n + 1
  end
  return n
end

local function has_ascii_word(text)
  return string.find(text or "", "[0-9A-Za-z]") ~= nil
end

local function emit_all(buffered, best_idx)
  if best_idx and best_idx > 1 then
    yield(buffered[best_idx])
    for i, c in ipairs(buffered) do
      if i ~= best_idx then yield(c) end
    end
  else
    for _, c in ipairs(buffered) do yield(c) end
  end
end

local function filter(input, env)
  local ctx = env.engine.context
  local raw = ctx.input or ""
  -- 用户显式使用分隔符：完全尊重手动切分，不干预
  if raw == "" or string.find(raw, "'", 1, true) then
    for cand in input:iter() do yield(cand) end
    return
  end
  local raw_len = string.len(raw)

  local buffered = {}
  local best_idx, best_syl = nil, nil
  local flushed = false
  local LOOKAHEAD = 12

  for cand in input:iter() do
    if flushed then
      yield(cand)
    else
      table.insert(buffered, cand)
      -- 只比较完整覆盖输入的纯中文候选（整句/整词）
      if (cand._end - cand.start) >= raw_len and not has_ascii_word(cand.text) then
        local syl = syllable_count(cand.preedit)
        if syl and (not best_syl or syl < best_syl) then
          best_syl, best_idx = syl, #buffered
        end
      end
      if #buffered >= LOOKAHEAD then
        emit_all(buffered, best_idx)
        buffered = {}
        flushed = true
      end
    end
  end
  if not flushed then
    emit_all(buffered, best_idx)
  end
end

return filter
