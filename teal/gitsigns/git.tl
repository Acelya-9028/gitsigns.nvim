require('gitsigns/async')

local gsd = require("gitsigns/debug")
local util = require('gitsigns/util')
local run_job = util.run_job

local parse_diff_line = require("gitsigns/hunks").parse_diff_line

local M = {}

function M.file_info(file: string, toplevel: string): cb_function
  return function(callback: function(string, string, string, boolean))
    local relpath: string
    local object_name: string
    local mode_bits: string
    local stage: number
    local has_conflict: boolean = false
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'ls-files',
        '--stage',
        '--others',
        '--exclude-standard',
        file
      },
      cwd = toplevel,
      on_stdout = function(_, line: string)
        local parts = vim.split(line, '%s+')
        if #parts > 1 then
          stage = tonumber(parts[3])
          if stage <= 1 then
              mode_bits   = parts[1]
              object_name = parts[2]
              relpath     = parts[4]
          else
              has_conflict = true
          end
        else
          relpath = parts[1]
        end
      end,
      on_exit = function(_, _)
        callback(relpath, object_name, mode_bits, has_conflict)
      end
    }
  end
end

function M.get_staged_txt(toplevel: string, relpath: string, stage: number): cb_function
  return function(callback: function({string}))
    local content: {string} = {}
    run_job {
      command = 'git',
      args = {'--no-pager', 'show', ':'..tostring(stage)..':'..relpath},
      cwd = toplevel,
      on_stdout = function(_, line: string)
        table.insert(content, line)
      end,
      on_exit = function(_, code: number)
        callback(code == 0 and content or nil)
      end
    }
  end
end

function M.run_blame(file: string, toplevel: string, lines: {string}, lnum: number): cb_function
  return function(callback: function({string:string}))
    local results: {string} = {}
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'blame',
        '--contents', '-',
        '-L', lnum..',+1',
        '--line-porcelain',
        file
      },
      writer = lines,
      cwd = toplevel,
      on_stdout = function(_, line: string)
        table.insert(results, line)
      end,
      on_exit = function()
        local ret: {string:string} = {}
        local header = vim.split(table.remove(results, 1), ' ')
        ret.sha = header[1]
        ret.abbrev_sha = string.sub(ret.sha, 1, 8)
        ret.orig_lnum = header[2]
        ret.final_lnum = header[3]
        for _, l in ipairs(results) do
          if not vim.startswith(l, '\t') then
            local cols = vim.split(l, ' ')
            local key = table.remove(cols, 1)
            ret[key] = table.concat(cols, ' ')
          end
        end
        callback(ret)
      end
    }
  end
end

local function process_abbrev_head(gitdir: string, head_str: string): string
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    if util.path_exists(gitdir..'/rebase-merge')
      or util.path_exists(gitdir..'/rebase-apply') then
      return '(rebasing)'
    elseif gsd.debug_mode then
      return head_str
    else
      return ''
    end
  end
  return head_str
end

function M.get_repo_info(path: string): cb_function
  return function(callback: function)
    local out = {}
    run_job {
      command = 'git',
      args = {'rev-parse',
        '--show-toplevel',
        '--absolute-git-dir',
        '--abbrev-ref', 'HEAD',
      },
      cwd = path,
      on_stdout = function(_, line: string)
        table.insert(out, line)
      end,
      on_exit = vim.schedule_wrap(function()
        local toplevel = out[1]
        local gitdir = out[2]
        local abbrev_head = process_abbrev_head(gitdir, out[3])
        callback(toplevel, gitdir, abbrev_head)
      end)
    }
  end
end

function M.stage_lines(toplevel: string, lines: {string}): cb_function
  return function(callback: function())
    local status = true
    local err = {}
    run_job {
      command = 'git',
      args = {'apply', '--cached', '--unidiff-zero', '-'},
      cwd = toplevel,
      writer = lines,
      on_stderr = function(_, line: string)
        status = false
        table.insert(err, line)
      end,
      on_exit = function()
        if not status then
          local s = table.concat(err, '\n')
          error('Cannot stage lines. Command stderr:\n\n'..s)
        end
        callback()
      end
    }
  end
end

function M.add_file(toplevel: string, file: string): cb_function
  return function(callback: function())
    local status = true
    local err = {}
    run_job {
      command = 'git',
      args = {'add', '--intent-to-add', file},
      cwd = toplevel,
      on_stderr = function(_, line: string)
        status = false
        table.insert(err, line)
      end,
      on_exit = function()
        if not status then
          local s = table.concat(err, '\n')
          error('Cannot add file. Command stderr:\n\n'..s)
        end
        callback()
      end
    }
  end
end

function M.run_diff(staged: string, text: {string}, diff_algo: string): cb_function
  return function(callback: function)
    local results: {Hunk} = {}
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'diff',
        '--color=never',
        '--diff-algorithm='..diff_algo,
        '--patch-with-raw',
        '--unified=0',
        staged,
        '-'
      },
      writer = text,
      on_stdout = function(_, line: string)
        if vim.startswith(line, '@@') then
          table.insert(results, parse_diff_line(line))
        else
          if #results > 0 then
            table.insert(results[#results].lines, line)
          end
        end
      end,
      on_stderr = function(_, line: string)
           -- On windows print() crashes in callback threads
           vim.schedule(function()
              print('error: ' .. line, 'NA', 'run_diff')
           end)
      end,
      on_exit = function()
        callback(results)
      end
    }
  end
end

return M
