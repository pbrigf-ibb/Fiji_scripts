/* by Aleksander Chlebowski
 * Warsaw, 15 May 2019 
 * 
 * Simplpe tool to examine overlays of colored plate montages.
 * 
 * The "master" directory is the directory where all data is stored. It is the parent of "plate views in color".
 * 
 */

master = getDirectory("Choose master directory");
directory = master + "plate views in color/"

// list all files
all_files = getFileList(directory);
// list all plate numbers
all_plates = newArray(all_files.length);
for (f = 0; f < all_files.length; f++) {
	filename_split = split(all_files[f], "._");
	all_plates[f] = filename_split[0];
}
// get uniques
plates = unique(all_plates);
// create dialog
Dialog.create("open plate");
Dialog.addChoice("choose plate", plates);
Dialog.show();
number = Dialog.getChoice();
// open image collection
plate_number = "^" + number;
run("Image Sequence...", "open=[" + directory + "] file=(" + plate_number + ") sort");


function unique(array) {
	sorted = Array.sort(array);
	uniques = Array.trim(sorted, 1);
	for (i = 1; i < array.length; i++) {
		if (sorted[i] != sorted[i-1]) uniques = Array.concat(uniques, array[i]);
	}
	return uniques;
}