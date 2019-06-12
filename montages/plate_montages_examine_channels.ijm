/* by Aleksander Chlebowski
 * Warsaw, 15 May 2019 
 * 
 * Simple tool to examine single-channel plate montages.
 * 
 * The "master" directory is the directory where all data is stored. It is the parent of "plate views".
 * 
 */

master = getDirectory("Choose master directory");
directory = master + "plate views/"

// list all files
all_files = getFileList(directory);
// list all plate numbers and all channels
all_plates = newArray(all_files.length);
all_channels = newArray(all_files.length);
for (f = 0; f < all_files.length; f++) {
	filename_split = split(all_files[f], "._");
	all_plates[f] = filename_split[0];
	all_channels[f] = filename_split[filename_split.length-2];
}
// get uniques
plates = unique(all_plates);
channels = unique(all_channels);
// create dialog
Dialog.create("open plate");
Dialog.addChoice("choose plate", plates);
Dialog.addChoice("choose channel", channels);
Dialog.show();
number = Dialog.getChoice();
channel = Dialog.getChoice();
// open image collection
plate_id = "^" + number + ".*" + channel;
run("Image Sequence...", "open=[" + directory + "] file=(" + plate_id + ") sort");

exit();

function unique(array) {
	sorted = Array.sort(array);
	uniques = Array.trim(sorted, 1);
	for (i = 1; i < array.length; i++) {
		if (sorted[i] != sorted[i-1]) uniques = Array.concat(uniques, array[i]);
	}
	return uniques;
}