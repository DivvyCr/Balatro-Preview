mkdir release/
mkdir release/DVPreview/
mkdir release/DVSimulate/

cp -r src/* release/DVPreview
cp lovely.toml release/DVPreview

cp -r $DVSIM_PATH/src/* release/DVSimulate
cp $DVSIM_PATH/lovely.toml release/DVSimulate

cd release/
zip -r DOWNLOAD.zip *
mv DOWNLOAD.zip ..
cd ..

rm -rf release/
