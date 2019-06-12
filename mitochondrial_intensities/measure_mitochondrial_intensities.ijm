/* by Aleksander Chlebowski
 * Warsaw, 6 February 2018
 */

/* Measure intensities of gfp and mitotracker channels in mitochondrial regions.
 * The macro is run each time a region of interest (more less one cell) is selected in the image stack.
 * Images are processed : slightly blurred and background subtracted (mito - automatically, gfp - with user input).
 * Objects are identified based on the (tresholded) mitotracker image.
 * Meaurements are made for all objects for the gfp and mito channels. They are written to a table with single objects in rows.
 * After measurments are done, the images are colored, have their brightness adjusted (non-interactively), and are put into a montage that is saved.
 * All image windows are closed, leaving only the original stack.
 * At this point the user can move to the next experiment (stack) or select another cell for analysis.
 * All measurement results are collected in the Results window and can be moved or saved to a file at any point.
  */

// MEASUREMENTS
// Currently the measurements taken entail ROI area and its mean and integrated gray values. 
// (The latter two may be used to calculate mean intensity throughout the cell.)

run("Set Measurements...", "area mean integrated redirect=None decimal=3");

// crop out selection and name it crop
run("Duplicate...", "title=crop duplicate");
// split to images
run("Stack to Images");
// go to mitochondrial channel; blow up, blur and subtract background
selectWindow("mito");
run("In [+]"); run("In [+]");
run("Gaussian Blur...", "sigma=0.50 slice");
run("Subtract Background...", "rolling=3 slice");
// set treshold automatically
setAutoThreshold("Yen dark");
// pause for user to be able to adjust the treshold
waitForUser("INTERACTION REQUIRED", "you can adjust the treshold");
// identify mitochondrial regions; ones at image border will be omitted
run("Analyze Particles...", "exclude clear add");
// go to gfp channel; blow up, set LUT, blur and subtract background (latter interactive)
selectWindow("gfp");
run("In [+]"); run("In [+]");
run("HiLo");
run("Gaussian Blur...", "sigma=0.50 slice");
run("Subtract Background...");
// put mito and gfp into stack (in that order)
run("Concatenate...", "  title=stack image1=mito image2=gfp");
// measure intensities in all ROIs for both channels
roiManager("multi-measure measure_all append"); roiManager("Delete");

// split stack again
run("Stack to Images");
// adjust display and set colors for all channels
selectWindow("gfp");
run("Enhance Contrast", "saturated=0.05"); run("Green"); run("RGB Color");
selectWindow("mito");
run("Enhance Contrast", "saturated=0.05"); run("Yellow"); run("RGB Color");
selectWindow("trans");
run("Enhance Contrast", "saturated=0.05"); run("Grays"); run("RGB Color");
// make stack
run("Concatenate...", "  title=stack image1=gfp image2=mito image3=trans");
setForegroundColor(50,50,50);
run("Make Montage...", "columns=3 rows=1 scale=1 border=5 use");
// save montage and get new name of its window
saveAs("tiff");
montage = getInfo("window.title");
// close all images other than the original stack and remove ROIs from manager
close("crop"); close("stack"); close(montage);

