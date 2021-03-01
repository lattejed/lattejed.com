echo `date` > .timestamp
git add .
git commit -am 'Roll up commit for deploying'
git push do master
