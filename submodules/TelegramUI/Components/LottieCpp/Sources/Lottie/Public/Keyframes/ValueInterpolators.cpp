#include "ValueInterpolators.hpp"

#include <Accelerate/Accelerate.h>

namespace lottie {

void batchInterpolate(std::vector<PathElement> const &from, std::vector<PathElement> const &to, BezierPath &resultPath, double amount) {
    int elementCount = (int)from.size();
    if (elementCount > (int)to.size()) {
        elementCount = (int)to.size();
    }
    
    if (sizeof(PathElement) == 8 * 2 * 3) {
        resultPath.setElementCount(elementCount);
        vDSP_vintbD((double *)&from[0], 1, (double *)&to[0], 1, &amount, (double *)&resultPath.elements()[0], 1, elementCount * 2 * 3);
    } else {
        for (int i = 0; i < elementCount; i++) {
            const auto &fromVertex = from[i].vertex;
            const auto &toVertex = to[i].vertex;
            
            auto vertex = ValueInterpolator<CurveVertex>::interpolate(fromVertex, toVertex, amount);
            
            resultPath.updateVertex(vertex, i, false);
        }
    }
}

}
