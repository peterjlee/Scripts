#@Context context
#@UIService uiService
#@LogService logService

# NN_Distances.py
# IJ BAR snippet https://github.com/tferr/Scripts/tree/master/Snippets
#
# Calculates the closest pair of points from a 2D/3D list of centroid
# coordinates (opened in the IJ 'Results' table), calling another BAR
# script to plot the frequencies of nearest neighbor distances.
#
# TF 20150810

import math, sys
from bar import Utils
import ij.measure.ResultsTable as RT

# Column headings listing x,y,z positions
xHeading, yHeading, zHeading = "X", "Y", "Z"


def plot_distributions():
    from bar import Runner
    runner = Runner(context)
    runner.runIJ1Macro("Data_Analysis/Distribution_Plotter.ijm", "NN distance")
    if not runner.scriptLoaded():
        uiService.showDialog("Distribution of NN distances not plotted.\n"
                           + "Check console for details", "Error")


def distance(x1, y1, z1, x2, y2, z2):
    """ Retrieves the distances betwenn two points """
    dx = (x1-x2)**2
    dy = (y1-y2)**2
    dz = (z1-z2)**2
    return math.sqrt(dx+dy+dz)


def getXYZPositons(rt, xcol_header, ycol_header, zcol_header):
    """ Retrieves valid data from the Results table """
    try:
        x = y = z = None
        x = rt.getColumn(rt.getColumnIndex(xcol_header))
        y = rt.getColumn(rt.getColumnIndex(ycol_header))
        z = rt.getColumn(rt.getColumnIndex(zcol_header))
    finally:
        return x, y, z


def calcNNDistances(rt, x, y, z=None):
    """ Calculates NN distances and adds them to the Results table """
    # Ignore Z positions?
    if z is None:
        logService.info("NN: Assuming 2D distances...")
        z = [0]*len(x)
    # Calculate distances for all positions. Retrieve NNs
    for i in range(len(x)):
        minDx = sys.maxint
        nearest = 0
        for j in range(len(x)):
            if i == j:
                continue
            dst = distance(x[i], x[j], y[i], y[j], z[i], z[j])
            if dst > 0 and dst < minDx:
                minDx = dst
                nearest = j+1
        rt.setValue("NN pair", i, nearest)
        rt.setValue("NN distance", i, minDx)


def main():
    rt = Utils.getResultsTable()
    if rt is None:
        return
    x, y, z = getXYZPositons(rt, xHeading, yHeading, zHeading)
    if not None in (x, y):
        # Do the calculations and sisplay appended results
        calcNNDistances(rt, x, y, z)
        rt.showRowNumbers(True)
        rt.show("Results")
        plot_distributions()
    else:
        uiService.showDialog("Data for X,Y positions not found.",
                             "Invalid Results Table")


main()
