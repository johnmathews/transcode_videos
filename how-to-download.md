This command will download the highest quality video and audio available, and then convert it to a format and codec that macOS can play using quickviewer, by default without needing to install extra quickview plugins.




There is an alias in ~/.aliases that will run the following command. Just run `yt <url>`.


`sudo yt-dlp -f bestvideo+bestaudio --recode-video mp4 --postprocessor-args "ConvertVideo:-c:v libx264 -preset veryslow -crf 14 -profile:v high -level 4.2 -pix_fmt yuv420p -c:a aac -b:a 320k" -o "~/Desktop/videos/%(title)s.%(ext)s" "<sharing-url>"`
