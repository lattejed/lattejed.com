echo `date` > .timestamp
git add .timestamp
git commit -m 'Deploy commit'
git push do master
