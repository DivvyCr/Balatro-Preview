rm -f DOWNLOAD.zip

mkdir release/
mkdir release/DVPreview/
mkdir release/DVSimulate/
mkdir release/DVSettings/

cp -r src/* release/DVPreview
cp lovely.toml release/DVPreview

cp -r $DVSIM_PATH/src/* release/DVSimulate
cp $DVSIM_PATH/lovely.toml release/DVSimulate

cp -r $DVSET_PATH/src/* release/DVSettings
cp $DVSET_PATH/lovely.toml release/DVSettings

cd release/
zip -r DOWNLOAD.zip *
mv DOWNLOAD.zip ..
cd ..

rm -rf release/
