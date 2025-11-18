运行结果

<img width="554" height="511" alt="图片2" src="https://github.com/user-attachments/assets/bb75a1c7-a8a7-4465-bdeb-c4f796f919a3" />

这是一个自动化的Linux系统监控脚本，可以检查：
- 磁盘使用情况
- 内存使用情况  
- 系统负载
- 服务状态

自动生成HTML报告，支持邮件通知。
# 运行监控脚本
./bin/system_check.sh
查看报告：
脚本会在 templates/ 目录生成HTML格式的监控报告，直接在浏览器中打开即可查看。
