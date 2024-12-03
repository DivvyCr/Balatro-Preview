mkdir release/
mkdir release/DVPreview/
mkdir release/DVSimulate/

cp -r src/* release/DVPreview
cp -r $DVSIM_PATH/src/* release/DVSimulate

cd release/
zip -r DOWNLOAD.zip *
mv DOWNLOAD.zip ..
cd ..

rm -rf release/
