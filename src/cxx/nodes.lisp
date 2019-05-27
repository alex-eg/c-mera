(in-package :cm-c++)

;;; ====================
;;;      c++ nodes
;;; ====================

(defnode superclass () (attribute superclass))
(defnode declaration-list-initializer () (list-items))
(defnode function-definition (pure virtual) (item parameter tail-qualifiers body))

(defstatement class () (name superclasses body))
(defstatement constructor () (name parameter initializer body))
(defstatement destructor (virtual) (name body))
(defstatement access-specifier (specifier) (body))
(defstatement namespace () (namespace body))
(defstatement using-namespace () (namespace))
(defstatement using () (item))
(defstatement template () (parameters body))
(defstatement try-block () (body catches))
(defstatement catch (all) (decl-item body))

(defexpression from-namespace () (namespace name))
(defexpression instantiate () (template arguments))
(defexpression new (operator) (specifier type))
(defexpression delete (operator) (object))
(defexpression lambda-definition () (capture parameter tail-qualifiers type body))
