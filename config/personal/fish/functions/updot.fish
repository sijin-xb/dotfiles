function updot -d "一键同步所有配置到 GitHub"
    # 1. 自动更新所有已追踪文件的变化
    # chezmoi re-add 会扫描所有已管理文件，并将家目录的改动同步到仓库目录
    echo "正在扫描配置更改..."
    chezmoi re-add

    # 2. 进入 chezmoi 仓库目录
    set -l chezmoi_dir (chezmoi source-path)
    pushd $chezmoi_dir

    # 3. Git 操作
    echo "正在准备推送到 GitHub..."
    git add .
    
    # 使用当前时间作为 Commit 信息
    set -l current_time (date "+%Y-%m-%d %H:%M:%S")
    git commit -m "Update dotfiles: $current_time"
    
    # 推送到远程仓库
    if git push origin main
        echo "✨ 同步成功！GitHub 仓库已更新。"
    else
        echo "❌ 推送失败，请检查网络或 Git 状态。"
    end

    # 4. 返回原来的目录
    popd
end
